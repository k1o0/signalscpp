classdef End
    % End  Deferred 'end' expression for use in signal indexing.
    %
    % Used by Signal.end() to preserve the 'end' keyword through
    % the subsref mechanism, resolving it only when the actual
    % array size is known.
    %
    % Example:
    %   last = sig.end(1, 1)  % represents 'end' for 1D indexing
    %   range = seq(end-5:end)  % last 6 elements

    properties
        Index       % which index dimension (k in end(k,n))
        NumIndices  % total number of index dimensions (n in end(k,n))
        Offset = 0  % offset to apply (for end-5, offset=-5)
    end

    methods
        function obj = End(k, n, offset)
            % End  Create a deferred 'end' expression
            %   obj = sig.End(k, n) creates an expression representing
            %   'end' for the k-th index dimension out of n dimensions.
            %   obj = sig.End(k, n, offset) creates 'end + offset'
            obj.Index = k;
            obj.NumIndices = n;
            if nargin > 2
                obj.Offset = offset;
            end
        end

        function idx = resolve(obj, value)
            % resolve  Compute the actual index based on array size
            %   idx = resolve(obj, value) computes the actual index
            %   that 'end' represents for the given value.
            sz = size(value);
            n = obj.NumIndices;
            k = obj.Index;

            % Handle case where indices span multiple dimensions
            if n < length(sz) && k == n
                sz(n) = prod(sz(n:end));
            end
            idx = sz(k) + obj.Offset;
        end

        function result = minus(obj, val)
            % minus  Support end-5 syntax
            if ~isa(obj, 'sig.End')
                % val - obj
                error('Cannot subtract sig.End from a scalar');
            end
            % obj - val: return new sig.End with offset
            result = sig.End(obj.Index, obj.NumIndices, obj.Offset - val);
        end

        function result = plus(obj, val)
            % plus  Support end+5 syntax
            if ~isa(obj, 'sig.End')
                % val + obj
                obj = val;
                val = obj;
            end
            % obj + val: return new sig.End with offset
            result = sig.End(obj.Index, obj.NumIndices, obj.Offset + val);
        end

        function result = colon(varargin)
            % colon  Support end-5:end syntax
            if nargin == 2
                result = sig.RangeEnd(varargin{1}, varargin{2});
            elseif nargin == 3
                result = sig.RangeEnd(varargin{1}, varargin{3}, varargin{2});
            else
                error('sig:signal:indexEndRangeError', ...
                    'Unsupported range expression involving end')
            end
        end

        function s = str(~)
            % str  String representation
            s = 'end';
        end
    end
end

