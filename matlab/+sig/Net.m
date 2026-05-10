classdef Net
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

        function affected = transact(obj, node, value)
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

        function n = get.nActiveNodes(obj)
            n = obj.Proxy.NActiveNodes();
        end

        function id = get.Id(obj)
            id = obj.Proxy.ID;   % uint64 assigned by ProxyManager at construction
        end

        function tf = isValid(obj)
            tf = obj.Proxy.IsValid();
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

