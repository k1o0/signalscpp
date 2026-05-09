classdef Net
% sig.Net  Reactive signal network (C++ backend via libmexclass proxy).
%
% USAGE
%   net = sig.Net()              % default 4 000 node slots
%   net = sig.Net(maxNodes)      % explicit limit
%
% METHODS
%   node     = net.addNode(inputNodes, opId, appendValues)
%              Returns a sig.Node handle.  inputNodes may be an array of
%              sig.Node objects, a numeric row vector of node ids, or [].
%   affected = net.transact(node, value)
%              net.apply(affected)
%   value    = net.getCurrentValue(node)
%   value    = net.getWorkingValue(node)
%   ids      = net.getNodeInputs(node)
%   n        = net.nActiveNodes()
%   tf       = net.isValid()
%              net.deleteNode(node)
%
% All methods that accept a node also accept a numeric node id for
% low-level use.

    properties (Access = private)
        Proxy
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
        % addNode  Create a new node and return a sig.Node handle.
        %   inputNodes   — sig.Node array, numeric id vector, or [] for sources
        %   opId         — numeric operation code (51=nop/source, 50=identity, …)
        %   appendValues — logical scalar
        %   fn           — (optional) MATLAB function handle for callable opcodes
        %                  (map_op=60, mapn_op=61, filter_op=62, scan_op=63)
            inputIds = sig.Net.toIds(inputNodes);
            if nargin < 5
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues));
            else
                proxyId = obj.Proxy.AddNode( ...
                    double(inputIds(:)'), double(opId), logical(appendValues), fn);
            end
            node = sig.Node(proxyId, obj);
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

        function n = nActiveNodes(obj)
            n = obj.Proxy.NActiveNodes();
        end

        function tf = isValid(obj)
            tf = obj.Proxy.IsValid();
        end

        function out = mapn(obj, inputNodes, fn)
        % mapn  Map N nodes through fn when any of them has a new value.
        %   inputNodes — array of sig.Node objects or numeric id vector
        %   fn         — function handle, e.g. @(a,b) a+b
        %   Returns a new sig.Node.
            out = obj.addNode(inputNodes, 61, false, fn);
        end

        function node = origin(obj, value)
        % origin  Create a constant "root" node with a pre-committed value.
        %   value — scalar constant (double, logical, or string).
        %   The node's CurrentValue equals value immediately; it never fires
        %   on its own but provides a stable latest value to downstream ops.
        %   Use this to supply constant seeds, thresholds, etc. as nodes.
            proxyId = obj.Proxy.AddNode(double.empty(1,0), double(51), false);
            node = sig.Node(proxyId, obj);
            affected = obj.Proxy.Transact(double(node.Id), value);
            if ~isempty(affected)
                obj.Proxy.Apply(double(affected(:)'));
            end
        end
    end

    % -----------------------------------------------------------------------
    % Static helpers: coerce a sig.Node | numeric id to a double scalar id
    % or a double row-vector of ids.
    % -----------------------------------------------------------------------
    methods (Static)
        function id = toId(node)
        % toId  Return numeric id from a sig.Node or a numeric scalar.
            if isa(node, 'sig.Node')
                id = node.Id;
            else
                id = double(node);
            end
        end

        function ids = toIds(nodes)
        % toIds  Return a double row vector from an array of sig.Node or
        %        numeric ids, or [] for an empty input.
            if isempty(nodes)
                ids = double.empty(1, 0);
            elseif isa(nodes, 'sig.Node')
                ids = double([nodes.Id]);
            else
                ids = double(nodes(:)');
            end
        end
    end
end
