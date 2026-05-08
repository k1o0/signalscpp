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
    end

    methods
        function obj = Node(proxyId)
        % Node  Wrap an existing C++ NodeProxy (created by sig.Net.addNode).
        %   proxyId — uint64 proxy ID returned by NetworkProxy::AddNode.
            arguments
                proxyId (1,1) uint64
            end
            obj.Proxy = libmexclass.proxy.Proxy( ...
                "Name", "sig.NodeProxy", ...
                "ID",   libmexclass.proxy.Identifier(proxyId));
            obj.Id = obj.Proxy.GetId();
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
