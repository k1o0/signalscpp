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
        % Network MEX proxy class
        Proxy libmexclass.proxy.Proxy

        Subscriptions  % containers.Map(double nodeId → sig.Signal)
    end

    properties (Dependent)
        % Unique ID per network instance, set at construction
        Id uint64

        % Number of nodes in use within network
        nActiveNodes uint64
    end

    properties (Transient)
        % A structure holding node ids, the values they should take and the
        % delay before they are applied.  Used for delayed posting of values.
        Schedule

        % For storing handles to Node update callbacks
        Listeners TidyHandle
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
            obj.Schedule = struct('nodeid', [], 'value', {}, 'when', []);
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

        function notifySubscribers(this, affected)
        % notifySubscribers  Deliver valueChanged to any signals registered via onValue.
        %   Called by post() after each apply cycle.
            if isempty(affected) || this.Subscriptions.Count == 0
                return
            end
            for ii = 1:numel(affected)
                nodeId = affected(ii);
                if this.Subscriptions.isKey(nodeId)
                    s = this.Subscriptions(nodeId);
                    if isvalid(s)
                        s.valueChanged(this.getCurrentValue(s.Node));
                    end
                end
            end
        end

        function runSchedule(this)
        % Apply values to nodes that are due to be updated
        %
        %   Applies values to nodes that are due to be updated, i.e. those that
        %   have a delayed post.  This method should be manually run or set as
        %   a callback in a timer function.
        %   Example:
        %     net = sig.Net; % Create network
        %     tmr = timer('TimerFcn', @(~,~)net.runSchedule,...
        %       'ExecutionMode', 'fixedrate', 'Period', 0.01);
        %     start(tmr) % Run schedule every 100 ms
        %     
        %     delayedSig = sig1.delay(5) % New signal delayed by 5 sec
        %     h = output(delayedSig);
        %     delayedPost(s, pi, 5) % Post to input signal also delayed by 5 sec
        %     ... 10 seconds later...
        %     3.1416
        %
        % See also sig.node.OriginSignal/delayedPost, sig.node.Signal/delay
          if numel(this.Schedule) > 0
            % slice out due tasks
            dueIdx = [this.Schedule.when] < GetSecs;
            dueTasks = this.Schedule(dueIdx);
            this.Schedule(dueIdx) = [];
            % work through them
            for ti = 1:numel(dueTasks)
              % dt = GetSecs - dueTasks(ti).when;
              affectedIdxs = submit(this.Id, dueTasks(ti).nodeid, dueTasks(ti).value);
              applyNodes(this.Id, affectedIdxs);
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

    methods (Access = {?sig.OriginSignal, ?sig.SubscriptableOriginSignal})
        function post(obj, node, value)
        % POST  Inject value into a node, propagate, and notify subscribers.
            if isa(node, 'sig.Signal'); node = node.Node; end
            affected = obj.transact(node, value);
            obj.apply(affected);
            obj.notifySubscribers(affected);
        end

    end

    methods %(Access = private)
        function deleteNode(obj, node)
            obj.Proxy.DeleteNode(node.Id);
        end
       
        function affected = transact(obj, node, value)
            if isa(node, 'sig.Signal'); node = node.Node; end
            % TODO Proxy should raise when posting to dependant nodes
            affected = obj.Proxy.Transact(node.Id, value);
        end

        function apply(obj, affected)
            if isempty(affected)
                return
            end
            obj.Proxy.Apply(double(affected(:)'));
        end

    end

end

