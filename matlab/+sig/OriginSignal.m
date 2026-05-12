classdef OriginSignal < sig.Signal
% sig.OriginSignal  Source signal to which values are injected manually.
%
% Created by sig.Net.origin().  Use post() to push a value through the network.
%
% METHODS
%   post(value)  Inject value into the network (transact + apply).
%
% See also sig.Signal, sig.Net.origin, sig.Net.rootNode

    methods

        function obj = OriginSignal(node)
        % OriginSignal  Wrap the given sig.Node; called by sig.Net.origin().
            obj = obj@sig.Signal(node);
        end

        function post(obj, value)
        % post  Inject value into the network and propagate to all dependents.
            obj.Node.Net.post(obj.Node, value);
        end

    end
end
