classdef Net
% sig.Net  Reactive signal network (C++ backend via libmexclass proxy).
%
% USAGE
%   net = sig.Net()              % default 4 000 node slots
%   net = sig.Net(maxNodes)      % explicit limit
%
% METHODS (directly wrapping NetworkProxy)
%   nodeId   = net.addNode(inputIds, opId, appendValues)
%   affected = net.transact(nodeId, value)
%              net.apply(affected)
%   value    = net.getCurrentValue(nodeId)
%   value    = net.getWorkingValue(nodeId)
%   ids      = net.getNodeInputs(nodeId)
%   n        = net.nActiveNodes()
%   tf       = net.isValid()
%              net.deleteNode(nodeId)

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

        function nodeId = addNode(obj, inputIds, opId, appendValues)
            nodeId = obj.Proxy.AddNode( ...
                double(inputIds(:)'), ...
                double(opId), ...
                logical(appendValues));
        end

        function deleteNode(obj, nodeId)
            obj.Proxy.DeleteNode(double(nodeId));
        end

        function affected = transact(obj, nodeId, value)
            affected = obj.Proxy.Transact(double(nodeId), value);
        end

        function apply(obj, affected)
            if isempty(affected)
                return
            end
            obj.Proxy.Apply(double(affected(:)'));
        end

        function value = getCurrentValue(obj, nodeId)
            value = obj.Proxy.GetCurrentValue(double(nodeId));
        end

        function value = getWorkingValue(obj, nodeId)
            value = obj.Proxy.GetWorkingValue(double(nodeId));
        end

        function ids = getNodeInputs(obj, nodeId)
            ids = obj.Proxy.GetNodeInputs(double(nodeId));
        end

        function n = nActiveNodes(obj)
            n = obj.Proxy.NActiveNodes();
        end

        function tf = isValid(obj)
            tf = obj.Proxy.IsValid();
        end
    end
end
