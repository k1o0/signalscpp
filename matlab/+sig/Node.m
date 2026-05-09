classdef Node < handle
% sig.Node  Handle to a single reactive node inside a sig.Net network.
%
% Node objects are created by sig.Net.addNode() — they cannot be
% constructed independently.
%
% PROPERTIES
%   Id           (read-only) node id within the network
%   CurrentValue (Dependent)  committed value after the last apply()
%   WorkingValue (Dependent)  in-transaction value ([] outside a transact)
%   InputIds     (Dependent)  row vector of upstream node ids
%
% TRANSFER METHODS (return new sig.Node handles)
%   out = node.map(fn)           — output = fn(input)
%   out = node.filter(fn)        — pass input when fn(input) is truthy
%   out = node.scan(fn, seed)    — fold: acc = fn(acc, input), seed = init acc
%   out = node.numel()           — output = number of elements in input
%
% The underlying C++ NodeProxy is owned by this object and is destroyed
% when MATLAB garbage-collects the sig.Node handle.

    properties (SetAccess = private)
        Id (1,1) double  % set once during construction
    end

    properties (Dependent)
        CurrentValue
        WorkingValue
        InputIds
    end

    properties (Access = private)
        Proxy
        Net_   % back-reference to parent sig.Net (may be [])
    end

    methods
        function obj = Node(proxyId, net)
        % Node  Wrap an existing C++ NodeProxy (created by sig.Net.addNode).
        %   proxyId — uint64 proxy ID returned by NetworkProxy::AddNode
        %   net     — (optional) parent sig.Net for chained transfer methods
            arguments
                proxyId (1,1) uint64
                net = []
            end
            obj.Proxy = libmexclass.proxy.Proxy( ...
                "Name", "sig.NodeProxy", ...
                "ID",   libmexclass.proxy.Identifier(proxyId));
            obj.Id = obj.Proxy.GetId();
            obj.Net_ = net;
        end

        % -----------------------------------------------------------------
        % Dependent property getters
        % -----------------------------------------------------------------

        function v = get.CurrentValue(obj)
            v = obj.Proxy.GetCurrentValue();
        end

        function v = get.WorkingValue(obj)
            v = obj.Proxy.GetWorkingValue();
        end

        function ids = get.InputIds(obj)
            ids = obj.Proxy.GetInputIds();
        end

        % -----------------------------------------------------------------
        % Transfer methods
        % -----------------------------------------------------------------

        function out = map(obj, fn)
        % map  Create a node whose value is fn applied to this node's value.
        %   fn — function handle, e.g. @(x) x*2
        %   Returns a new sig.Node.
            obj.requireNet_('map');
            out = obj.Net_.addNode(obj, 60, false, fn);
        end

        function out = filter(obj, fn)
        % filter  Pass this node's value through when fn(value) is truthy.
        %   fn — predicate function handle, e.g. @(x) x > 0
        %   Returns a new sig.Node.
            obj.requireNet_('filter');
            out = obj.Net_.addNode(obj, 62, false, fn);
        end

        function out = scan(obj, fn, seed)
        % scan  Running accumulator (fold): acc = fn(acc, new_value).
        %   fn   — function handle with signature f(accumulator, value)
        %   seed — initial accumulator value or a sig.Node that resets the
        %          accumulator when it fires.
        %   Returns a new sig.Node whose current value is the accumulator.
            obj.requireNet_('scan');
            if isa(seed, 'sig.Node')
                seedNode = seed;
            else
                seedNode = obj.Net_.origin(seed);
            end
            out = obj.Net_.addNode([obj, seedNode], 63, false, fn);
        end

        function out = numel(obj)
        % numel  Output the number of elements of this node's value.
        %   Returns a new sig.Node.
            obj.requireNet_('numel');
            out = obj.Net_.addNode(obj, 30, false);
        end
    end

    methods (Access = private)
        function requireNet_(obj, methodName)
            if isempty(obj.Net_)
                error('sig:noNet', ...
                    'sig.Node.%s requires the node to be owned by a sig.Net. Create nodes via sig.Net.addNode().', ...
                    methodName);
            end
        end
    end
end

