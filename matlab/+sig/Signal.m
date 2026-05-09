classdef (Abstract) Signal < handle
% sig.Signal  Abstract interface for reactive signals.
%
% This class defines the complete user-facing API for signals.  It is never
% instantiated directly — users receive sig.node.Signal (or one of its
% subclasses) from sig.Net.origin() and the transfer methods.
%
% All operator overloads (+, -, *, /, comparisons, etc.) are implemented
% here as concrete methods in terms of the abstract combinators, so they
% require no re-implementation in subclasses.
%
% ABSTRACT COMBINATORS (must be overridden in sig.node.Signal)
%   map, map2, mapn, filter, scan
%   at, keepWhen, to, setTrigger, setEpochTrigger
%   identity, skipRepeats, delta, delay, lag
%   bufferUpTo, buffer
%   merge, selectFrom, indexOfFirst, cond
%   onValue, output
%
% See also sig.node.Signal, sig.node.OriginSignal, sig.Net

    %% Abstract combinators
    methods (Abstract)

        % out = s.map(f)
        % Returns a signal whose value is f(s) whenever s updates.
        % f may be a function handle.  See sig.node.Signal.map.
        out = map(obj, f)

        % out = s.map2(s2, f)
        % Returns a signal whose value is f(s, s2) whenever either updates.
        out = map2(obj, other, f)

        % out = mapn(s1, s2, ..., f)
        % Returns a signal (or signals) by applying f to all inputs.
        varargout = mapn(obj, varargin)

        % out = s.filter(f)
        % Passes s through when f(s) is truthy; suppresses otherwise.
        out = filter(obj, f)

        % out = s.scan(f, seed)
        % Fold: accumulator = f(accumulator, new_value).
        % seed — initial accumulator value, or a signal that resets it.
        out = scan(obj, f, seed)

        % out = s.at(when)
        % Samples s's latest value whenever 'when' takes a truthy value.
        out = at(obj, when)

        % out = s.keepWhen(when)
        % Passes new values of s through only while 'when' is truthy.
        out = keepWhen(obj, when)

        % out = a.to(b)
        % True from when a fires a truthy value until b fires a truthy value.
        out = to(obj, b)

        % out = arm.setTrigger(release)
        % True once: fires when 'release' becomes truthy after 'arm'.
        out = setTrigger(obj, release)

        % out = period.setEpochTrigger(t, x, threshold)
        % Fires when x does not change by more than threshold over period.
        out = setEpochTrigger(obj, t, x, threshold)

        % out = s.identity()
        % Returns a dependent signal equal to s (forces ordering guarantee).
        out = identity(obj)

        % out = s.skipRepeats()
        % Suppresses updates when the new value equals the current value.
        out = skipRepeats(obj)

        % out = s.delta()
        % Returns the difference between consecutive values of s.
        out = delta(obj)

        % out = s.delay(period)
        % Returns s delayed by 'period' seconds.
        out = delay(obj, period)

        % out = s.lag(n)
        % Returns s delayed by n update steps.
        out = lag(obj, n)

        % out = s.bufferUpTo(n)
        % Holds the last n values of s (fires as soon as any arrive).
        out = bufferUpTo(obj, nSamples)

        % out = s.buffer(n)
        % Holds exactly the last n values (fires only once n are available).
        out = buffer(obj, nSamples)

        % out = merge(s1, s2, ...)
        % Takes the value of whichever input fires first in each tick.
        out = merge(obj, varargin)

        % out = idx.selectFrom(opt1, opt2, ...)
        % Takes the value of the option indexed by idx.
        out = selectFrom(obj, varargin)

        % out = indexOfFirst(s1, s2, ...)
        % Index (1-based) of the first signal with a truthy value.
        out = indexOfFirst(obj, varargin)

        % out = cond(pred1, val1, pred2, val2, ...)
        % Value of the first val whose pred is truthy.
        out = cond(obj, value1, varargin)

        % h = s.onValue(f)
        % Calls f(value) every time s takes a new value.  Returns a handle
        % whose deletion removes the listener.
        h = onValue(obj, f)

        % h = s.output()
        % Prints s's value to the command window each time it updates.
        % Equivalent to s.onValue(@disp).
        h = output(obj)

    end

    %% Concrete operator overloads (implemented in terms of map / map2 / mapn)
    methods

        function b = floor(a)
            b = a.map(@floor);
        end

        function b = abs(a)
            b = a.map(@abs);
        end

        function b = sign(a)
            b = a.map(@sign);
        end

        function b = sin(a)
            b = a.map(@sin);
        end

        function b = cos(a)
            b = a.map(@cos);
        end

        function b = uminus(a)
            b = a.map(@uminus);
        end

        function b = not(a)
            b = a.map(@not);
        end

        function b = exp(a)
            b = a.map(@exp);
        end

        function b = sqrt(a)
            b = a.map(@sqrt);
        end

        function b = erf(a)
            b = a.map(@erf);
        end

        function b = transpose(a)
            b = a.map(@transpose);
        end

        function b = fliplr(a)
            b = a.map(@fliplr);
        end

        function b = flipud(a)
            b = a.map(@flipud);
        end

        function b = str2num(a)
            b = a.map(@str2num);
        end

        function b = numel(a)
            b = a.map(@numel);
        end

        function c = plus(a, b)
            c = map2(a, b, @plus);
        end

        function c = minus(a, b)
            c = map2(a, b, @minus);
        end

        function c = times(a, b)
            c = map2(a, b, @times);
        end

        function c = mtimes(a, b)
            c = map2(a, b, @mtimes);
        end

        function c = rdivide(a, b)
            c = map2(a, b, @rdivide);
        end

        function c = mrdivide(a, b)
            c = map2(a, b, @mrdivide);
        end

        function c = mpower(a, b)
            c = map2(a, b, @mpower);
        end

        function c = power(a, b)
            c = map2(a, b, @power);
        end

        function c = mod(a, b)
            c = map2(a, b, @mod);
        end

        function c = strcmp(a, b)
            c = map2(a, b, @strcmp);
        end

        function c = eq(a, b, handleComparison)
            % eq  Signal equality, or handle identity when handleComparison=true.
            % The handleComparison flag is used internally (e.g., by unique())
            % to distinguish object identity from reactive equality.
            if nargin >= 3 && handleComparison
                c = eq@handle(a, b);
            else
                c = map2(a, b, @eq);
            end
        end

        function c = ne(a, b, handleComparison)
            if nargin >= 3 && handleComparison
                c = ne@handle(a, b);
            else
                c = map2(a, b, @ne);
            end
        end

        function c = gt(a, b)
            c = map2(a, b, @gt);
        end

        function c = ge(a, b)
            c = map2(a, b, @ge);
        end

        function c = lt(a, b)
            c = map2(a, b, @lt);
        end

        function c = le(a, b)
            c = map2(a, b, @le);
        end

        function c = and(a, b)
            c = map2(a, b, @and);
        end

        function c = or(a, b)
            c = map2(a, b, @or);
        end

        function y = vertcat(varargin)
            y = mapn(varargin{:}, @vertcat);
        end

        function y = horzcat(varargin)
            y = mapn(varargin{:}, @horzcat);
        end

        function b = rot90(a, k)
            if nargin < 2
                b = a.map(@rot90);
            else
                b = map2(a, k, @rot90);
            end
        end

        function b = any(a, dim)
            if nargin < 2
                b = a.map(@any);
            else
                b = map2(a, dim, @any);
            end
        end

        function b = all(a, dim)
            if nargin < 2
                b = a.map(@all);
            else
                b = map2(a, dim, @all);
            end
        end

        function b = sum(a, dim)
            if nargin < 2
                b = a.map(@sum);
            else
                b = map2(a, dim, @sum);
            end
        end

        function b = num2str(a, precision)
            if nargin < 2
                b = a.map(@num2str);
            else
                b = map2(a, precision, @num2str);
            end
        end

        function b = round(a, N, type)
            if nargin < 2
                b = a.map(@round);
            elseif nargin < 3
                b = map2(a, N, @round);
            else
                b = mapn(a, N, type, @round);
            end
        end

        function varargout = min(A, B, dim)
            if nargin < 2
                [varargout{1:nargout}] = A.mapn(@min);
            elseif nargin < 3
                [varargout{1:nargout}] = mapn(A, B, @min);
            else
                [varargout{1:nargout}] = mapn(A, B, dim, @min);
            end
        end

        function varargout = max(A, B, dim)
            if nargin < 2
                [varargout{1:nargout}] = A.mapn(@max);
            elseif nargin < 3
                [varargout{1:nargout}] = mapn(A, B, @max);
            else
                [varargout{1:nargout}] = mapn(A, B, dim, @max);
            end
        end

        function b = size(a, dim)
            if nargin < 2
                b = a.map(@size);
            else
                b = map2(a, dim, @size);
            end
        end

    end
end
