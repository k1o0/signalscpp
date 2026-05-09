classdef Node < handle
% sig.Node  Low-level MEX shim around a single C++ NodeProxy.
%
% sig.Node is an internal class.  User code should work with the richer
% sig.node.Signal / sig.node.OriginSignal classes returned by sig.Net.
%
% PROPERTIES
%   Id           (read-only) node id within the network
%   CurrentValue (Dependent)  committed value after the last apply()
%   WorkingValue (Dependent)  in-transaction value ([] outside a transact)
%   InputIds     (Dependent)  row vector of upstream node ids
%
% The underlying C++ NodeProxy is owned by this object and is destroyed
% when MATLAB garbage-collects the sig.Node handle.
%
% See also sig.node.Signal, sig.node.OriginSignal, sig.Net

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

    end
end

