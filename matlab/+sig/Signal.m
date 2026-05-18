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

    properties (Hidden, Access = private)
        OnValueCallbacks   % containers.Map(int32 → function_handle), lazy init
        NextCallbackId int32 = int32(0)
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

        function m = map(this, f, formatSpec)
            % MAP Evaluate a function on each signal update.
            %
            % ds = s.map(f, [formatSpec]) returns a signal which takes the value
            % resulting from mapping function f onto the value in s (i.e. f(s)). If
            % f is not a function, f is mapped to ds whenever s takes a value.
            %
            % Inputs:
            %   f (function_handle|any) - a function to pass the value of this
            %     signal to. If f is a contstant or another it's value is used
            %     each time this updates.
            %   format_spec (char) - optional format specification string for
            %     name display.
            %
            % Outputs:
            %   s (sig.Signal) - a signal that takes the value of f(this) or f
            %     depending on whether f is a function handle.
            %
            % Examples:
            %   f = @(x) x.^2; % the function to be mapped
            %   ds = s.map(f); % ds = s^2
            %   m = s.map(pi); % m = pi whenever s updates
            %
            % See also SIG.SIGNAL/MAP2, SIG.SIGNAL/MAPN

            if nargin < 3; formatSpec = sprintf('%%s.map(%s)', toStr(f)); end
            net = this.Node.Net;
            if isa(f, 'function_handle')
                if strcmp(net.TransferMode, 'matlab')
                    transFcn = @(values, states) sig.transfer.map(values, states, f);
                    m = sig.Signal(net.addNode(this.Node, sig.OpCode.function_op, false, transFcn));
                else
                    m = sig.Signal(net.addNode(this.Node, sig.OpCode.map_op, false, f));
                end
                m.Node.FormatSpec = formatSpec;
                m.Node.DisplayInputs = this.Node;
            else
                % Constant or signal: f_node holds the value to sample when this fires.
                if isa(f, 'sig.Signal'); f_node = f.Node; else; f_node = net.rootNode(f); end
                % For a signal, override the baked-in name with a dynamic placeholder.
                if nargin < 3 && isa(f, 'sig.Signal')
                    formatSpec = '%s.map(%s)';
                end
                nodes = [this.Node, f_node];
                if strcmp(net.TransferMode, 'matlab')
                    transFcn = @(values, states) sig.transfer.mapVal(values, states);
                    m = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
                else
                    % No callable: map_op samples inputs[1] when inputs[0] fires.
                    m = sig.Signal(net.addNode(nodes, sig.OpCode.map_op, false));
                end
                m.Node.FormatSpec    = formatSpec;
                if isa(f, 'sig.Signal'); m.Node.DisplayInputs = nodes;
                else;                  m.Node.DisplayInputs = this.Node; end
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
                transFcn = @(values, states) sig.transfer.mapn(values, states, f);
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
        %   Multi-output: [X, Y] = a.mapn(b, @meshgrid)
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
            nodes  = refNode.from(rawInputs{:});
            net    = refNode.Net;
            nout   = max(1, nargout);

            % Build FormatSpec: mapn(in0, in1, ..., @fn)
            fn_str  = toStr(f);
            n_nodes = numel(nodes);
            phs     = strjoin(repmat({'%s'}, 1, n_nodes), ', ');
            fmt     = sprintf('mapn(%s, %s)', phs, fn_str);

            if nout == 1
                if strcmp(net.TransferMode, 'matlab')
                    transFcn = @(values, states) sig.transfer.mapn(values, states, f);
                    varargout{1} = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
                else
                    varargout{1} = sig.Signal(net.addNode(nodes, sig.OpCode.mapn_op, false, f));
                end
                varargout{1}.Node.FormatSpec    = fmt;
                varargout{1}.Node.DisplayInputs = nodes;
            else
                % Pack all outputs into a cell, then unpack per output.
                pack_f = @(varargin) pack_outputs(f, nout, varargin{:});
                if strcmp(net.TransferMode, 'matlab')
                    transFcn = @(values, states) sig.transfer.mapn(values, states, pack_f);
                    packNode = net.addNode(nodes, sig.OpCode.function_op, false, transFcn);
                else
                    packNode = net.addNode(nodes, sig.OpCode.mapn_op, false, pack_f);
                end
                packNode.FormatSpec    = fmt;
                packNode.DisplayInputs = nodes;
                packSig    = sig.Signal(packNode);
                pack_name  = packNode.Name;
                for i = 1:nout
                    varargout{i} = packSig.map(@(c) c{i});
                    if i == 1
                        varargout{i}.Node.Name = pack_name;
                    else
                        varargout{i}.Node.Name = sprintf('%s[%d]', pack_name, i);
                    end
                end
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
            %   s (sig.Signal) - a signal that updates to true after 'set' 
            %     and 'release' update in that order
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
                transFcn = @(values, states) sig.transfer.filter(values, states, f);
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

        function s = subscriptable(this)
        % subscriptable  Wrap this signal in a sig.SubscriptableSignal.
        %   Dot-subscripting the result (e.g. s.fieldName) creates a derived
        %   signal whose value is the named field of this signal's value.
        %
        %   See also sig.SubscriptableSignal, sig.Net/subscriptableOrigin
            s = sig.SubscriptableSignal(this.Node);
        end

        function fs = flattenStruct(this)
        % flattenStruct  Derive a signal that expands signal-valued struct fields.
        %
        %   Returns a new signal that fires whenever the blueprint signal (this)
        %   fires with an updated struct, or whenever any signal-valued field of
        %   that struct fires.  The output is a plain struct with all fields
        %   resolved to their current values.
        %
        %   The set of signal fields is dynamic: each time the blueprint fires,
        %   the C++ callable re-inspects the struct and rewires as needed.
        %   Output is suppressed until all signal fields have at least one value.
        %
        %   Example:
        %     s = net.subscriptableOrigin('s');
        %     s.x = xSig;   s.y = ySig;
        %     flat = s.flattenStruct();   % flat follows s, replacing x/y with current values
        %
        %   See also sig.SubscriptableSignal, sig.Signal/flatten
            net  = this.Node.Net;
            node = net.addNode(this.Node, sig.OpCode.flatten_struct_op, false);
            node.FormatSpec    = '%s.flattenStruct()';
            node.DisplayInputs = this.Node;
            fs = sig.Signal(node);
        end

        function out = flatten(this)
        % flatten  Unwrap a signal-of-signals.
        %
        %   When this signal fires with a sig.Signal value S, flatten subscribes
        %   to S: future updates from S pass through directly.  When this signal
        %   fires with a plain value, that value is output immediately.
        %
        %   Example:
        %     director = net.origin('director');
        %     s1 = net.origin('s1');
        %     flat = director.flatten();
        %     director.post(s1);   % flat now mirrors s1
        %     s1.post(42);         % flat takes value 42
        %
        %   See also sig.Signal/flattenStruct
            net  = this.Node.Net;
            node = net.addNode(this.Node, sig.OpCode.flatten_op, false);
            node.FormatSpec    = '%s.flatten()';
            node.DisplayInputs = this.Node;
            out = sig.Signal(node);
        end

        function out = at(this, when)
            % AT  Sample this signal's value whenever 'when' fires true.
            %
            %   out = at(this, when) returns a dependent signal that takes the
            %   latest value of 'this' at the moment 'when' fires with a truthy
            %   value.  The output fires in response to 'when' updating, not
            %   'this' — unlike keepWhen, posting a new value to 'this' alone
            %   does not cause output to fire.
            %
            % Inputs:
            %   this (sig.Signal) - the signal whose value to sample
            %   when (sig.Signal) - the gate signal; output fires each time
            %                       this updates with a truthy value
            %
            % Outputs:
            %   out (sig.Signal) - fires with the current value of 'this'
            %                      whenever 'when' fires truthy
            %
            % Examples:
            %   x_on_press = x.at(keyboard);  % sample x on each key press
            %   % Equivalent using then:
            %   x_on_press = keyboard.then(x);
            %
            % See also sig.Signal/then, sig.Signal/keepWhen
            net = this.Node.Net;
            if isa(when, 'sig.Signal')
                when_node = when.Node;
            else
                when_node = net.rootNode(when);
            end
            out = sig.Signal(net.addNode([this.Node, when_node], sig.OpCode.at_op, false));
            out.Node.FormatSpec    = '%s.at(%s)';
            out.Node.DisplayInputs = [this.Node, when_node];
        end

        function out = then(this, what)
            % THEN  Sample 'what' whenever this signal fires with a truthy value.
            %
            %   out = then(this, what) is equivalent to what.at(this): fires
            %   the latest value of 'what' whenever 'this' (the gate) fires
            %   truthy.  The name reads naturally: "when [this fires], then
            %   [take what]".
            %
            % Inputs:
            %   this (sig.Signal) - the gate signal; output fires each time
            %                       this updates with a truthy value
            %   what (sig.Signal) - the signal whose value to sample
            %
            % Outputs:
            %   out (sig.Signal) - fires with the current value of 'what'
            %                      whenever 'this' fires truthy
            %
            % Examples:
            %   x_on_press = keyboard.then(x);  % equivalent to x.at(keyboard)
            %   confirmed  = confirm_btn.then(choice);
            %
            % See also sig.Signal/at, sig.Signal/keepWhen
            net = this.Node.Net;
            if isa(what, 'sig.Signal')
                what_node = what.Node;
            else
                what_node = net.rootNode(what);
            end
            out = sig.Signal(net.addNode([what_node, this.Node], sig.OpCode.at_op, false));
            out.Node.FormatSpec    = '%s.then(%s)';
            out.Node.DisplayInputs = [this.Node, what_node];
        end

        % =================================================================
        % Stubs for ops not yet backed by C++ opcodes
        % =================================================================

        function s = keepWhen(this, when)
            % KEEPWHEN Pass through this value whenever it fires and gate is truthy.
            %
            % s = keepWhen(what, when) returns a dependent signal which takes the
            % value of 'what' whenever it updates, provided 'when' evaluates
            % true.
            %
            % Note: 's' fires only when 'this' fires; 'when' is sampled 
            % lazily at that moment.to sample the value of 'this' whenever 
            % 'when' updates, use the 'at' method. 
            %
            % Inputs:
            %   this (sig.Signal) - a signal whose values to take
            %   when (sig.Signal) - a signal whose current value gates output.
            %
            % Outputs:
            %   s (sig.Signal) - a signal that takes the value of 'this'
            %   only if 'when' is truthy.
            %
            % Examples:
            %   s = what.keepWhen(x > 1); % when x > 1, s == what
            %   s = what.keepWhen(true); % identity; s === what
            %
            % See also SIG.NODE.SIGNAL/FILTER

            net = this.Node.Net;
            if isa(when, 'sig.Signal')
                gate_node = when.Node;
            else
                gate_node = net.rootNode(when);
            end
            if strcmp(net.TransferMode, 'matlab')s
                transFcn = @(values, states) sig.transfer.keepWhen(values, states, gate_node);
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.function_op, false, transFcn));
            else
                s = sig.Signal(net.addNode([this.Node, gate_node], sig.OpCode.keep_when, false));
            end
            s.Node.FormatSpec = '%s.keepWhen(%s)';
            s.Node.DisplayInputs = [this.Node, gate_node];
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

        function h = onValue(this, f)
        % onValue  Register a callback invoked each time this signal takes a value.
        %   h = s.onValue(@(v) disp(v)) calls the function with the new value
        %   whenever the signal fires.  Deleting h (or letting it go out of scope)
        %   removes the subscription automatically.
        %
        %   Returns a TidyHandle; keep it in scope for as long as the subscription
        %   should remain active.
        %
        %   See also TidyHandle
            if isempty(this.OnValueCallbacks)
                this.OnValueCallbacks = ...
                    containers.Map('KeyType', 'int32', 'ValueType', 'any');
            end
            callbackidx = this.NextCallbackId + int32(1);
            this.NextCallbackId = callbackidx;
            this.OnValueCallbacks(callbackidx) = f;
            if this.OnValueCallbacks.Count == 1
                this.Node.Net.registerSubscription(double(this.Node.Id), this);
            end
            h = TidyHandle(@unsub);
            function unsub()
                if isvalid(this) && ~isempty(this.OnValueCallbacks) && ...
                        isKey(this.OnValueCallbacks, callbackidx)
                    this.OnValueCallbacks.remove(callbackidx);
                    if this.OnValueCallbacks.Count == 0
                        this.Node.Net.unregisterSubscription(double(this.Node.Id));
                    end
                end
            end
        end

        function valueChanged(this, newValue)
        % valueChanged  Invoke all registered onValue callbacks with newValue.
        %   Called by sig.Net.notifySubscribers after each apply cycle.
            if isempty(this.OnValueCallbacks) || this.OnValueCallbacks.Count == 0
                return
            end
            callbacks = this.OnValueCallbacks.values();
            for ii = 1:numel(callbacks)
                callbacks{ii}(newValue);
            end
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

        function [varargout] = subsref(this, s)
        % subsref  () subscripts create derived signals; others use builtin.
            if strcmp(s(1).type, '()')
                subs = s(1);
                out = this.map(@(v) builtin('subsref', v, subs));
                inpform = strJoin(repmat({'%s'}, 1, numel(subs)), ',');
                out.Node.formatSpec = ['%s(' inpform ')'];
                if length(s) > 1
                    [varargout{1:nargout}] = subsref(out, s(2:end));
                else
                    varargout = {out};
                end
            else
                [varargout{1:nargout}] = builtin('subsref', this, s);
            end
        end

    end
end
