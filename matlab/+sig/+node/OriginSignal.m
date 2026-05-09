classdef OriginSignal < sig.node.Signal
% sig.node.OriginSignal  A source signal whose values are posted by user code.
%
% OriginSignals are created by sig.Net.origin().  They form the entry
% points of a reactive network — all other signals are derived from them
% via transfer methods (map, filter, scan, etc.).
%
% METHODS
%   post(value)  — inject a new value and propagate through the network
%
% Example:
%   net = sig.Net();
%   x   = net.origin();          % sig.node.OriginSignal
%   y   = x.map(@(v) v * 2);    % sig.node.Signal
%   x.post(5);                   % y.CurrentValue is now 10
%
% See also sig.node.Signal, sig.Net

    methods

        function post(obj, value)
        % post  Inject a value into the reactive network and propagate it.
        %   The value is committed synchronously: all dependent signals are
        %   updated before post() returns.
            affected = obj.Net_.transact(obj, value);
            obj.Net_.apply(affected);
        end

    end

end
