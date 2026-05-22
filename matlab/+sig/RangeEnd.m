classdef RangeEnd
    % RangeEnd  Deferred colon expression involving sig.End.
    %
    % Preserves ranges like 5:end or end-5:end through MATLAB's parsing so
    % they can be resolved once the indexed signal value is available.

    properties
        Start
        Stop
        Step = []
    end

    methods
        function obj = RangeEnd(startVal, stopVal, stepVal)
            obj.Start = startVal;
            obj.Stop = stopVal;
            if nargin > 2
                obj.Step = stepVal;
            end
        end

        function idx = resolve(obj, value)
            startVal = sig.RangeEnd.resolvePart(obj.Start, value);
            stopVal = sig.RangeEnd.resolvePart(obj.Stop, value);
            if isempty(obj.Step)
                idx = startVal:stopVal;
            else
                idx = startVal:obj.Step:stopVal;
            end
        end

        function s = str(obj)
            if isempty(obj.Step)
                s = sprintf('%s:%s', sig.RangeEnd.partToString(obj.Start), ...
                    sig.RangeEnd.partToString(obj.Stop));
            else
                s = sprintf('%s:%s:%s', sig.RangeEnd.partToString(obj.Start), ...
                    sig.RangeEnd.partToString(obj.Step), ...
                    sig.RangeEnd.partToString(obj.Stop));
            end
        end
    end

    methods (Static, Access = private)
        function value = resolvePart(part, arrayValue)
            if isa(part, 'sig.End')
                value = part.resolve(arrayValue);
            else
                value = part;
            end
        end

        function s = partToString(part)
            if isa(part, 'sig.End')
                if part.Offset == 0
                    s = 'end';
                elseif part.Offset > 0
                    s = sprintf('end+%d', part.Offset);
                else
                    s = sprintf('end%d', part.Offset);
                end
            else
                s = toStr(part);
            end
        end
    end
end