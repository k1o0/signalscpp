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

        function delayedPost(obj, value, delay)
        % delayedPost  Schedule a delayed update to this signal.
        %
        %   obj.delayedPost(value, delay)
        %   obj.delayedPost({value, delay})
        %
        %   Queues an update to this signal after the specified delay.
        %   The value is posted when Net.runSchedule() is called after the delay.
        %
        %   Inputs:
        %     value — the value to post
        %     delay — delay in seconds
        %
        %   Example:
        %     s.delayedPost(pi, 5)  % post pi after 5 seconds
        %
        %   See also sig.Net/runSchedule, sig.Signal/delay

            if nargin < 3
                % Value is a cell {value, delay}
                [value, delay] = value{:};
            end
            % Get current time (use now for compatibility, but note timing precision)
            t = now;
            % Add entry to schedule
            obj.Node.Net.Schedule(end + 1) = struct( ...
                'nodeid', obj.Node.Id, ...
                'value', {value}, ...
                'when', t + delay / (24 * 3600));  % convert delay from seconds to days
        end

    end
end
