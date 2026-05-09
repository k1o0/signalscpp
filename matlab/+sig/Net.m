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
%
% CREATING SIGNALS
%   x = net.origin()   % sig.node.OriginSignal — inject values with x.post(value)
%   y = x.map(fn)      % sig.node.Signal derived from x
%
% INTERNAL METHODS (used by sig.node.Signal transfer implementations)
%   node     = net.addNode(inputNodes, opId, appendValues)
%   node     = net.addNode(inputNodes, opId, appendValues, fn)
%   affected = net.transact(node, value)
%              net.apply(affected)
%
% All methods that accept a node also accept a numeric node id.

    properties (Access = private)
        Proxy
    end

    properties (Dependent)
        Id           % uint64 — unique per network instance, set at construction
        nActiveNodes
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
        % addNode  Create a new network node, return a sig.node.Signal.
        %   inputNodes   — sig.Signal / sig.Node array, cell-array mix, numeric
        %                  id vector, or [] for source nodes
        %   opId         — numeric opcode (51=nop, 50=identity, 30=numel,
        %                  60=map, 61=mapn, 62=filter, 63=scan)
        %   appendValues — logical scalar
        %   fn           — (optional) MATLAB function handle (opcodes 60–63)
            inputIds = sig.Net.toIds(inputNodes);
            if nargin < 5
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues));
            else
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues), fn);
            end
            node = sig.node.Signal(proxyId, obj);
        end

        function deleteNode(obj, node)
            obj.Proxy.DeleteNode(double(sig.Net.toId(node)));
        end

        function affected = transact(obj, node, value)
            affected = obj.Proxy.Transact(double(sig.Net.toId(node)), value);
        end

        function apply(obj, affected)
            if isempty(affected)
                return
            end
            obj.Proxy.Apply(double(affected(:)'));
        end

        function value = getCurrentValue(obj, node)
            value = obj.Proxy.GetCurrentValue(double(sig.Net.toId(node)));
        end

        function value = getWorkingValue(obj, node)
            value = obj.Proxy.GetWorkingValue(double(sig.Net.toId(node)));
        end

        function ids = getNodeInputs(obj, node)
            ids = obj.Proxy.GetNodeInputs(double(sig.Net.toId(node)));
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

        function node = origin(obj)
        % origin  Create a source (nop) node.  Inject values with node.post(value).
            proxyId = obj.Proxy.AddNode(double.empty(1, 0), double(51), false);
            node = sig.node.OriginSignal(proxyId, obj);
        end
    end

    % -----------------------------------------------------------------------
    % Static helpers
    % -----------------------------------------------------------------------
    methods (Static)

        function id = toId(node)
        % toId  Coerce a sig.Signal, sig.Node, or numeric scalar to a double id.
            if isa(node, 'sig.Signal') || isa(node, 'sig.Node')
                id = node.Id;
            else
                id = double(node);
            end
        end

        function ids = toIds(nodes)
        % toIds  Coerce inputs to a double row-vector of node ids.
        %   Accepts: [] | cell array | sig.Signal | sig.Node | numeric vector
            if isempty(nodes)
                ids = double.empty(1, 0);
            elseif iscell(nodes)
                ids = cellfun(@sig.Net.toId, nodes);
            elseif isa(nodes, 'sig.Signal') || isa(nodes, 'sig.Node')
                n   = builtin('numel', nodes);   % bypass overridden numel
                ids = zeros(1, n);
                for k = 1:n
                    ids(k) = nodes(k).Id;
                end
            else
                ids = double(nodes(:)');
            end
        end

    end
end

