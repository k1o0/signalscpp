classdef Net < handle
% sig.Net  Reactive signal network (C++ backend via libmexclass proxy).
%
% USAGE
%   net = sig.Net()              % default 4 000 node slots
%   net = sig.Net(maxNodes)      % explicit limit
%
% PROPERTIES
%   Id           (uint64, read-only) unique identifier for this network instance
%   nActiveNodes (double, read-only) number of nodes currently in use
%   TransferMode ('cpp' | 'matlab') how new combinator nodes are implemented:
%      'cpp'    (default) each combinator uses its named C++ opcode
%               (map_op=60, filter_op=62, …).  The MATLAB function handle is
%               stored on the node as a callable but gating & dispatch are
%               done in C++.  Use this for maximum performance.
%      'matlab' each combinator falls back to function_op (opcode 0) and a
%               MATLAB closure that implements the full transfer semantics.
%               Mirrors legacy sig.transfer.* approach for debugging or
%               custom-transfer experiments.
%
% CREATING SIGNALS
%   x = net.origin()   % sig.OriginSignal — inject values with x.post(value)
%   y = x.map(fn)      % sig.Signal derived from x
%
% INTERNAL METHODS (used by sig.Signal transfer implementations)
%   node     = net.addNode(inputNodes, opId, appendValues)
%   node     = net.addNode(inputNodes, opId, appendValues, fn)
%   affected = net.transact(node, value)
%              net.apply(affected)
%
% All methods that accept a node also accept a numeric node id.

    properties (Access = private)
        Proxy libmexclass.proxy.Proxy
        Subscriptions  % containers.Map(double nodeId → sig.Signal)
    end

    properties
        TransferMode (1,:) char {mustBeMember(TransferMode, {'cpp','matlab'})} = 'matlab'
    end

    properties (Dependent)
        % Unique ID per network instance, set at construction
        Id uint64

        % Number of nodes in use within network
        nActiveNodes uint64
    end

    methods
        function obj = Net(maxNodes)
            if nargin < 1
                maxNodes = 4000;
            end
            obj.Proxy = libmexclass.proxy.Proxy( ...
                "Name", "sig.NetworkProxy", ...
                "ConstructorArguments", {double(maxNodes)});
            obj.Subscriptions = containers.Map('KeyType', 'double', 'ValueType', 'any');
        end

        % -----------------------------------------------------------------

        function node = addNode(obj, inputNodes, opId, appendValues, fn)
        % addNode  Create a new network node; return a sig.Node handle.
        %   inputNodes   — sig.Node array for source nodes
        %   opId         — sig.OpCode constant or plain double
        %                  (see matlab/+sig/OpCode.m for the full list)
        %   appendValues — logical scalar
        %   fn           — (optional) MATLAB function handle (opcodes 60–63)
            inputIds = iff(isempty(inputNodes), [], @()[inputNodes.Id]);
            if nargin < 5
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues));
            else
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues), fn);
            end
            node = sig.Node(proxyId, obj, inputNodes);
        end

        function deleteNode(obj, node)
            obj.Proxy.DeleteNode(node.Id);
        end

        function post(obj, node, value)
        % post  Inject value into a node, propagate, and notify subscribers.
            if isa(node, 'sig.Signal'); node = node.Node; end
            affected = obj.transact(node, value);
            obj.apply(affected);
            obj.notifySubscribers(affected);
        end

        function affected = transact(obj, node, value)
            if isa(node, 'sig.Signal'); node = node.Node; end
            affected = obj.Proxy.Transact(node.Id, value);
        end

        function apply(obj, affected)
            if isempty(affected)
                return
            end
            obj.Proxy.Apply(double(affected(:)'));
        end

        function value = getCurrentValue(obj, node)
            value = obj.Proxy.GetCurrentValue(node.Id);
        end

        function value = getWorkingValue(obj, node)
            value = obj.Proxy.GetWorkingValue(node.Id);
        end

        function ids = getNodeInputs(obj, node)
            ids = obj.Proxy.GetNodeInputs(node.Id);
        end

        function setNodeInputs(obj, node, newInputIds)
        % setNodeInputs  Dynamically rewire a node's inputs at runtime.
        %   Used internally by flatten_op and flatten_struct_op callables.
        %   node         — sig.Node or sig.Signal
        %   newInputIds  — numeric array of node IDs (doubles)
            if isa(node, 'sig.Signal'); node = node.Node; end
            obj.Proxy.SetNodeInputs(node.Id, double(newInputIds(:)'));
        end

        function n = get.nActiveNodes(obj)
            n = obj.Proxy.NActiveNodes();
        end

        function id = get.Id(obj)
            id = obj.Proxy.ID;   % uint64 assigned by ProxyManager at construction
        end

        function tf = isValid(obj)
            tf = obj.Proxy.IsValid();
        end

        function registerSubscription(obj, nodeId, signal)
        % registerSubscription  Register signal to receive valueChanged calls.
        %   Called automatically by sig.Signal.onValue when the first callback
        %   is added to a signal.
            obj.Subscriptions(nodeId) = signal;
        end

        function unregisterSubscription(obj, nodeId)
        % unregisterSubscription  Remove subscription for the given node.
        %   Called automatically by the TidyHandle cleanup in sig.Signal.onValue
        %   when the last callback is removed.
            if obj.Subscriptions.isKey(nodeId)
                obj.Subscriptions.remove(nodeId);
            end
        end

        function notifySubscribers(obj, affected)
        % notifySubscribers  Deliver valueChanged to any signals registered via onValue.
        %   Called by post() after each apply cycle.
            if isempty(affected) || obj.Subscriptions.Count == 0
                return
            end
            for ii = 1:numel(affected)
                nodeId = affected(ii);
                if obj.Subscriptions.isKey(nodeId)
                    s = obj.Subscriptions(nodeId);
                    if isvalid(s)
                        s.valueChanged(obj.getCurrentValue(s.Node));
                    end
                end
            end
        end

        function s = subscriptableOrigin(obj, name)
        % subscriptableOrigin  Create a subscriptable origin signal.
        %
        %   s = net.subscriptableOrigin()       anonymous subscriptable origin
        %   s = net.subscriptableOrigin(name)   named subscriptable origin
        %
        %   The returned sig.SubscriptableOriginSignal supports:
        %     s.fieldName = value   post a struct update (subsasgn)
        %     x = s.fieldName       derive a new signal from a field (subsref)
        %     flat = s.flattenStruct()  expand signal-valued fields
        %
        %   See also sig.Net/origin, sig.SubscriptableOriginSignal
            n = obj.addNode(sig.Node.empty(), sig.OpCode.nop, false);
            if nargin < 2
                n.Name = sprintf("n%i", n.Id);
            else
                n.Name = name;
            end
            s = sig.SubscriptableOriginSignal(n);
        end

        function s = origin(obj, name)
            % Create an origin signal with a specified name
            %  Returns a signal of the class 'OriginSignal', which can have its
            %  values set via the post method.  The name is an optional string
            %  identifier.
            %
            %  Example:
            %   net = sig.Net; % Create network
            %   inputSig = net.origin('input');
            %   post(inputSig, pi)
            %   inputSig.Node.Value
            %   >> ans =
            %          3.1416
            %
            % See also sig.OriginSignal, sig.Net.subscriptableOrigin
            n = obj.addNode(sig.Node.empty(), sig.OpCode.nop, false);
            if nargin < 2
                n.Name = sprintf("n%i", n.Id);
            else
                n.Name = name;
            end
            s = sig.OriginSignal(n);
        end

        function n = rootNode(obj, value)
        % rootNode  Create a constant node initialised with value; return its sig.Node.
        %   The returned sig.Node reference keeps the C++ node alive.  The
        %   intermediate sig.OriginSignal is discarded once this method returns.
            s = obj.origin();
            s.post(value);
            n = s.Node;
            n.Name = toStr(value);
        end
    end

end

