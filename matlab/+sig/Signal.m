classdef Signal < handle
    % SIG.SIGNAL Reactive signal backed by a network node.
    %   This class contains the methods for connecting signals within a
    %   network. These methods create a new signal or a TidyHandle object (a
    %   listener for Signals events). The principle subclass to
    %   this is SIG.NODE.SIGNAL.
    %
    %   Instances are returned by sig.Net.origin(), and all transfer methods
    %   (map, filter, scan, etc.).  Do not construct directly.
    %
    %   COMBINATORS
    %     map, map2, mapn, filter, scan, identity, nElems
    %
    %   OPERATOR OVERLOADS (all implemented via map / map2 / mapn)
    %     Arithmetic:  + - * / .* ./ .^ ^  uminus
    %     Logical:     & | ~  ==  ~=  >  >=  <  <=
    %     Math:        floor abs sign sin cos exp sqrt erf transpose
    %                  fliplr flipud str2num num2str rot90
    %     Aggregation: any all sum min max sz
    %     Concatenation: vertcat horzcat
    %
    %   Example:
    %     net = sig.Net;
    %     a = net.origin('A');
    %     b = a^2;
    %
    % See also SIG.NODE, SIG.NET, SIG.ORIGINSIGNAL

    properties (Dependent)
        Name string
    end

    properties (Hidden, SetAccess = private)
        % The underlying network node
        Node sig.Node
    end

    methods

        function obj = Signal(node)
        % Signal  Store the given sig.Node; called internally by sig.Net combinators.
            obj.Node = node;
        end

        function v = get.Name(this)
            v = this.Node.Name;
        end

        function set.Name(this, v)
            this.Node.Name = v;
        end

        % =================================================================
        % Core combinators
        % =================================================================

        function s = map(this, f)
        % map  New signal = f(this_value) on every update.
            net = this.Node.Net;
            if strcmp(net.TransferMode, 'matlab')
                inputIds = double(this.Node.Id);
                transFcn = @(node) sig.transfer.map(net, inputIds, node, f);
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.function_op, false, transFcn));
            else
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.map_op, false, f));
            end
        end

        function s = map2(sig1, sig2, f)
        % map2  New signal = f(sig1, sig2) whenever either fires.
        %   Either argument may be a constant — it is wrapped automatically.
        %   Note: MATLAB may dispatch here with sig1 as a numeric constant
        %   (e.g., 3 + signal) due to class-precedence rules.
            if isa(sig1, 'sig.Signal')
                refNode = sig1.Node;
            elseif isa(sig2, 'sig.Signal')
                refNode = sig2.Node;
            else
                error('sig:noNet', 'map2: neither argument is a sig.Signal.');
            end
            nodes = refNode.from(sig1, sig2);
            net   = refNode.Net;
            if strcmp(net.TransferMode, 'matlab')
                inputIds = cellfun(@(n) double(n.Id), nodes);
                transFcn = @(node) sig.transfer.mapn(net, inputIds, node, f);
                s = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
            else
                s = sig.Signal(net.addNode(nodes, sig.OpCode.mapn_op, false, f));
            end
        end

        function varargout = mapn(varargin)
        % mapn  New signal(s) by applying f to N input signals/constants.
        %   Call as:  out = s1.mapn(s2, ..., sN, f)
        %          or: out = mapn(s1, s2, ..., sN, f)   (MATLAB dispatch)
        %   f is always the last argument; all preceding args are inputs.
            f         = varargin{end};
            rawInputs = varargin(1:end-1);
            refNode   = [];
            for k = 1:numel(rawInputs)
                if isa(rawInputs{k}, 'sig.Signal')
                    refNode = rawInputs{k}.Node;
                    break;
                end
            end
            assert(~isempty(refNode), 'sig:noNet', ...
                'mapn: no sig.Signal found in inputs.');
            nodes = refNode.from(rawInputs{:});
            net   = refNode.Net;
            if strcmp(net.TransferMode, 'matlab')
                inputIds = cellfun(@(n) double(n.Id), nodes);
                transFcn = @(node) sig.transfer.mapn(net, inputIds, node, f);
                varargout{1} = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
            else
                varargout{1} = sig.Signal(net.addNode(nodes, sig.OpCode.mapn_op, false, f));
            end
        end

        function s = filter(this, f, criterion)
            % FILTER Pass values through when f(value) equals criterion.  
            % 
            % If the function is a char array the variable may be omitted
            % for brevity, e.g. '~= 2' instead of 'x ~= 2'.  The values
            % that evaluate to true are kept, unless criterion == false, in
            % which case the other values are kept.
            %
            % Inputs:
            %   f (function_handle|char) - a function that returns a logical
            %     value.
            %   criterion (logical|sig.Signal) - when true (default) the values
            %     that evaluate true are kept.  When false, the values that don't
            %     pass are kept.
            %
            % Outputs:
            %   s - a signal that updates to true after 'set' and 'release'
            %     update in that order
            %
            % Examples:
            %   chrs = x.filter(@ischar);
            %   positive = x.filter('> 0');
            %   filtered = x.filter(@(x) 5 < x && x < 10);
            %   outOfRange = x.filter(@(x) 5 < x && x < 10, false);
            %
            % See also SIG.SIGNAL/KEEPWHEN

            if nargin < 3, criterion = true; end
            if ischar(f)
                f = str2func(['@(x)' iff(f(1) == 'x', f, ['x' f])]);
            end
            % Validate the function as best we can
            assert(nargin(f) > 0, 'function must accept at least one input arg')
            assert(nargout(f) ~= 0, 'function must return at least one output arg')

            net = this.Node.Net;
            if strcmp(net.TransferMode, 'matlab')
                nodes    = this.Node.from(this, criterion);
                inputIds = [nodes.Id];
                transFcn = @(node) sig.transfer.filter(net, inputIds, node, f);
                s = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
            else
                if isa(criterion, 'sig.Signal') || isa(criterion, 'sig.Node')
                    error('sig:criterionSignal', ...
                        'Signal criterion requires TransferMode=''matlab''');
                end
                pred = @(x) isequal(f(x), criterion);
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.filter_op, false, pred));
            end
            s.Node.DisplayInputs = s.Node.Inputs(1); % Don't display criterion
            s.Node.FormatSpec = sprintf('%%s.filter(%s)', toStr(f));
        end

        function s = scan(this, f, seed)
        % scan  Running fold: acc = f(acc, new_value).
        %   seed — initial accumulator value, or a signal that resets it.
            nodes = this.Node.from(this, seed);
            s = sig.Signal(this.Node.Net.addNode(nodes, sig.OpCode.scan_op, false, f));
        end

        function s = nElems(this)
        % nElems  New signal whose value is numel(this_value).
            s = sig.Signal(this.Node.Net.addNode(this.Node, sig.OpCode.numel_op, false));
        end

        function s = identity(this)
        % identity  New signal that mirrors this signal (ordering guarantee).
            s = sig.Signal(this.Node.Net.addNode(this.Node, sig.OpCode.identity, false));
        end

        % =================================================================
        % Stubs for ops not yet backed by C++ opcodes
        % =================================================================

        function out = at(obj, when) %#ok<INUSD>
            error('sig:notImplemented', 'at() is not yet implemented.');
        end

        function out = keepWhen(obj, when) %#ok<INUSD>
            error('sig:notImplemented', 'keepWhen() is not yet implemented.');
        end

        function out = to(obj, b) %#ok<INUSD>
            error('sig:notImplemented', 'to() is not yet implemented.');
        end

        function out = setTrigger(obj, release) %#ok<INUSD>
            error('sig:notImplemented', 'setTrigger() is not yet implemented.');
        end

        function out = setEpochTrigger(obj, t, x, threshold) %#ok<INUSD>
            error('sig:notImplemented', 'setEpochTrigger() is not yet implemented.');
        end

        function out = skipRepeats(obj)
            error('sig:notImplemented', 'skipRepeats() is not yet implemented.');
        end

        function out = delta(obj)
            error('sig:notImplemented', 'delta() is not yet implemented.');
        end

        function out = delay(obj, period) %#ok<INUSD>
            error('sig:notImplemented', 'delay() is not yet implemented.');
        end

        function out = lag(obj, n) %#ok<INUSD>
            error('sig:notImplemented', 'lag() is not yet implemented.');
        end

        function out = bufferUpTo(obj, nSamples) %#ok<INUSD>
            error('sig:notImplemented', 'bufferUpTo() is not yet implemented.');
        end

        function out = buffer(obj, nSamples) %#ok<INUSD>
            error('sig:notImplemented', 'buffer() is not yet implemented.');
        end

        function out = merge(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'merge() is not yet implemented.');
        end

        function out = selectFrom(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'selectFrom() is not yet implemented.');
        end

        function out = indexOfFirst(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'indexOfFirst() is not yet implemented.');
        end

        function out = cond(obj, value1, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'cond() is not yet implemented.');
        end

        function h = onValue(obj, f) %#ok<INUSD>
            error('sig:notImplemented', 'onValue() is not yet implemented.');
        end

        function h = output(obj)
            error('sig:notImplemented', 'output() is not yet implemented.');
        end

        % =================================================================
        % Operator overloads — all implemented via map / map2 / mapn
        % =================================================================

        function b = floor(a),     b = a.map(@floor);      end
        function b = abs(a),       b = a.map(@abs);         end
        function b = sign(a),      b = a.map(@sign);        end
        function b = sin(a),       b = a.map(@sin);         end
        function b = cos(a),       b = a.map(@cos);         end
        function b = uminus(a),    b = a.map(@uminus);      end
        function b = not(a),       b = a.map(@not);         end
        function b = exp(a),       b = a.map(@exp);         end
        function b = sqrt(a),      b = a.map(@sqrt);        end
        function b = erf(a),       b = a.map(@erf);         end
        function b = transpose(a), b = a.map(@transpose);   end
        function b = fliplr(a),    b = a.map(@fliplr);      end
        function b = flipud(a),    b = a.map(@flipud);      end
        function b = str2num(a),   b = a.map(@str2num);     end %#ok<ST2NM>

        function c = plus(a, b),    c = map2(a, b, @plus);    end
        function c = minus(a, b),   c = map2(a, b, @minus);   end
        function c = times(a, b),   c = map2(a, b, @times);   end
        function c = mtimes(a, b),  c = map2(a, b, @mtimes);  end
        function c = rdivide(a, b), c = map2(a, b, @rdivide); end
        function c = mrdivide(a,b), c = map2(a, b, @mrdivide);end
        function c = mpower(a, b),  c = map2(a, b, @mpower);  end
        function c = power(a, b),   c = map2(a, b, @power);   end
        function c = mod(a, b),     c = map2(a, b, @mod);     end
        function c = strcmp(a, b),  c = map2(a, b, @strcmp);  end
        function c = gt(a, b),      c = map2(a, b, @gt);      end
        function c = ge(a, b),      c = map2(a, b, @ge);      end
        function c = lt(a, b),      c = map2(a, b, @lt);      end
        function c = le(a, b),      c = map2(a, b, @le);      end
        function c = and(a, b),     c = map2(a, b, @and);     end
        function c = or(a, b),      c = map2(a, b, @or);      end

        function c = eq(a, b, handleComparison)
        % eq  Signal equality, or handle identity when handleComparison=true.
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

        function y = vertcat(varargin), y = mapn(varargin{:}, @vertcat); end
        function y = horzcat(varargin), y = mapn(varargin{:}, @horzcat); end

        function b = rot90(a, k)
            if nargin < 2, b = a.map(@rot90);
            else,          b = map2(a, k, @rot90); end
        end

        function b = any(a, dim)
            if nargin < 2, b = a.map(@any);
            else,          b = map2(a, dim, @any); end
        end

        function b = all(a, dim)
            if nargin < 2, b = a.map(@all);
            else,          b = map2(a, dim, @all); end
        end

        function b = sum(a, dim)
            if nargin < 2, b = a.map(@sum);
            else,          b = map2(a, dim, @sum); end
        end

        function b = num2str(a, precision)
            if nargin < 2, b = a.map(@num2str);
            else,          b = map2(a, precision, @num2str); end
        end

        function b = round(a, N, type)
            if nargin < 2,     b = a.map(@round);
            elseif nargin < 3, b = map2(a, N, @round);
            else,              b = mapn(a, N, type, @round); end
        end

        function varargout = min(A, B, dim)
            if nargin < 2,     [varargout{1:nargout}] = A.mapn(@min);
            elseif nargin < 3, [varargout{1:nargout}] = mapn(A, B, @min);
            else,              [varargout{1:nargout}] = mapn(A, B, dim, @min); end
        end

        function varargout = max(A, B, dim)
            if nargin < 2,     [varargout{1:nargout}] = A.mapn(@max);
            elseif nargin < 3, [varargout{1:nargout}] = mapn(A, B, @max);
            else,              [varargout{1:nargout}] = mapn(A, B, dim, @max); end
        end

        function b = sz(a, dim)
        % sz  New signal whose value is size(this_value[, dim]).
            if nargin < 2, b = a.map(@size);
            else,          b = map2(a, dim, @size); end
        end

    end
end
