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
            if strcmp(net.TransferMode, 'matlab')
                transFcn = @(values, states) sig.transfer.keepWhen(values, states, gate_node);
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.function_op, false, transFcn));
            else
                s = sig.Signal(net.addNode([this.Node, gate_node], sig.OpCode.keep_when, false));
            end
            s.Node.FormatSpec = '%s.keepWhen(%s)';
            s.Node.DisplayInputs = [this.Node, gate_node];
        end

        function out = to(this, release)
            % TO  Boolean signal that is true between two events.
            %
            %   out = to(this, release) returns a dependent signal with a
            %   logical value.  When 'this' (the arm signal) fires truthy,
            %   'out' updates to true.  When 'release' subsequently fires
            %   truthy, 'out' updates to false.  Re-arming or re-releasing
            %   without the counterpart firing has no effect.
            %
            % Inputs:
            %   this    (sig.Signal) - arm signal; truthy update sets out true
            %   release (sig.Signal) - release signal; truthy update (after
            %                         arm) resets out to false
            %
            % Outputs:
            %   out (sig.Signal) - logical signal; true between arm and
            %                      release events, false thereafter
            %
            % Examples:
            %   stimOn = onset.to(offset);  % true while stimulus is shown
            %   inWindow = entered.to(exited);
            %
            % See also sig.Signal/at, sig.Signal/keepWhen
            net = this.Node.Net;
            if isa(release, 'sig.Signal')
                release_node = release.Node;
            else
                release_node = net.rootNode(release);
            end
            out = sig.Signal(net.addNode([this.Node, release_node], sig.OpCode.latch, false));
            out.Node.FormatSpec    = '%s.to(%s)';
            out.Node.DisplayInputs = [this.Node, release_node];
        end

        function tr = setTrigger(this, release)
            % SETTRIGGER  Fire true once per arm/release cycle.
            %
            %   tr = setTrigger(this, release) returns a signal that fires
            %   true once when 'release' updates truthy after 'this' has
            %   updated.  Subsequent 'release' updates are ignored until
            %   'this' updates again, re-arming the trigger.
            %
            % Inputs:
            %   this    (sig.Signal) - arm signal; re-enables the trigger on
            %                          each update
            %   release (sig.Signal) - release signal; fires the trigger when
            %                          it updates truthy while armed
            %
            % Outputs:
            %   tr (sig.Signal) - fires true each time the arm/release
            %                     sequence completes
            %
            % Examples:
            %   responseMade = trialStart.setTrigger(wheelThreshold);
            %
            % See also sig.Signal/to, sig.Signal/at
            net = this.Node.Net;
            if isa(release, 'sig.Signal')
                release_node = release.Node;
            else
                release_node = net.rootNode(release);
            end
            armed     = this.to(release);
            not_armed = ~armed;
            true_node = net.rootNode(true);
            tr = sig.Signal(net.addNode([true_node, not_armed.Node], sig.OpCode.at_op, false));
            tr.Node.FormatSpec    = '%s.setTrigger(%s)';
            tr.Node.DisplayInputs = [this.Node, release_node];
        end

        function out = setEpochTrigger(obj, t, x, threshold) %#ok<INUSD>
            error('sig:notImplemented', 'setEpochTrigger() is not yet implemented.');
        end

        function out = skipRepeats(this)
            % SKIPREPEATS  Pass through only values that differ from the previous one.
            %
            %   out = this.skipRepeats() fires whenever the input value differs
            %   from the most recently committed value.  Repeated identical
            %   values are suppressed.  The first value always passes through.
            %
            %   For scalar doubles, equality is tested in C++.  For all other
            %   types the MATLAB isequal() built-in is used as a fallback.
            %
            % Outputs:
            %   out (sig.Signal) - fires only when value changes
            %
            % See also sig.Signal/keepWhen, sig.Signal/filter
            net = this.Node.Net;
            out = sig.Signal(net.addNode(this.Node, sig.OpCode.skip_repeats, false));
            out.Node.FormatSpec    = '%s.skipRepeats()';
            out.Node.DisplayInputs = this.Node;
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

        function bup = bufferUpTo(this, nSamples, typeChange)
            % BUFFERUPTO  Accumulate up to nSamples recent values in a typed or cell array.
            %
            %   bup = this.bufferUpTo(nSamples) accumulates double values into a
            %   1×N double row vector (matching legacy behaviour).  A type change
            %   raises an error.
            %
            %   bup = this.bufferUpTo(nSamples, 'cell') silently promotes the buffer
            %   to a 1×N cell array on the first type change and continues in cell
            %   mode thereafter.
            %
            % Inputs:
            %   this       (sig.Signal) - input signal to buffer
            %   nSamples   (scalar | sig.Signal) - maximum number of samples to keep
            %   typeChange (char, optional) - pass 'cell' to allow mixed-type buffering
            %
            % Outputs:
            %   bup (sig.Signal) - buffered values; 1×N double by default or 1×N cell
            %                      if 'cell' option used or a type change occurred
            %
            % See also sig.Signal/buffer
            net = this.Node.Net;
            if isa(nSamples, 'sig.Signal')
                n_node = nSamples.Node;
            else
                n_node = net.rootNode(nSamples);
            end
            if nargin > 2 && strcmpi(typeChange, 'cell')
                % Dummy callable signals cast mode to the C++ transfer block;
                % it is never invoked — its presence is the flag.
                castMarker = @(varargin) [];
                bup = sig.Signal(net.addNode([this.Node, n_node], ...
                    sig.OpCode.buffer_up_to, false, castMarker));
            else
                bup = sig.Signal(net.addNode([this.Node, n_node], ...
                    sig.OpCode.buffer_up_to, false));
            end
            bup.Node.FormatSpec    = '%s.bufferUpTo(%s)';
            bup.Node.DisplayInputs = [this.Node, n_node];
        end

        function b = buffer(this, nSamples, typeChange)
            % BUFFER  Rolling window: fire a full buffer once nSamples values accumulate.
            %
            %   b = this.buffer(nSamples) fires a 1×nSamples double row vector once
            %   the rolling window is full; suppresses output while filling.
            %
            %   b = this.buffer(nSamples, 'cell') uses a cell array buffer, allowing
            %   mixed-type values (see bufferUpTo for details).
            %
            % Inputs:
            %   this       (sig.Signal) - input signal to buffer
            %   nSamples   (scalar | sig.Signal) - required buffer length
            %   typeChange (char, optional) - pass 'cell' to allow mixed-type buffering
            %
            % Outputs:
            %   b (sig.Signal) - fires when buffer is full
            %
            % See also sig.Signal/bufferUpTo
            net  = this.Node.Net;
            if nargin > 2
                bup = this.bufferUpTo(nSamples, typeChange);
            else
                bup = this.bufferUpTo(nSamples);
            end
            full = (bup.nElems() == nSamples);
            b    = bup.keepWhen(full);
            if isa(nSamples, 'sig.Signal')
                n_node = nSamples.Node;
            else
                n_node = net.rootNode(nSamples);
            end
            b.Node.FormatSpec    = '%s.buffer(%s)';
            b.Node.DisplayInputs = [this.Node, n_node];
        end

        function m = merge(varargin)
            % MERGE  Signal that takes the value of whichever input fires most recently.
            %
            %   m = merge(s1, s2, ..., sN) returns a signal which updates
            %   whenever any input fires, taking that input's value.  When
            %   multiple inputs fire in the same transaction the earliest in
            %   the argument list wins.
            %
            %   merge(s1, s2) may also be called as s1.merge(s2) — MATLAB
            %   dispatches to this method for any call where at least one
            %   argument is a sig.Signal.
            %
            % Inputs:
            %   s1..sN (sig.Signal) - two or more signals to merge
            %
            % Outputs:
            %   m (sig.Signal) - fires with the value of the most-recently
            %                    updated input
            %
            % Examples:
            %   latest = merge(left, right);      % fires when either fires
            %   m = a.merge(b, c);                % method-call form
            %
            % See also sig.Signal/at, sig.Signal/keepWhen
            refNode = [];
            for k = 1:numel(varargin)
                if isa(varargin{k}, 'sig.Signal')
                    refNode = varargin{k}.Node;
                    break;
                end
            end
            assert(~isempty(refNode), 'sig:noNet', 'merge: no sig.Signal in inputs.');
            nodes = refNode.from(varargin{:});
            net   = refNode.Net;
            n     = numel(nodes);
            fmt   = ['( ' strjoin(repmat({'%s'}, 1, n), ' ~ ') ' )'];
            m = sig.Signal(net.addNode(nodes, sig.OpCode.merge, false));
            m.Node.FormatSpec    = fmt;
            m.Node.DisplayInputs = nodes;
        end

        function s = selectFrom(this, varargin)
            % SELECTFROM  Select a value by 0-based index.
            %
            %   s = selectFrom(this, opt0, opt1, ...) returns a signal that
            %   fires the latest value of the option addressed by 'this'
            %   (0-based) whenever the index or the selected option updates.
            %
            % Inputs:
            %   this (sig.Signal) - 0-based integer index signal
            %   opt0..optN        - signals or constants to select among
            %
            % Outputs:
            %   s (sig.Signal) - fires the selected option's latest value
            %
            % Examples:
            %   s = idx.selectFrom(a, b, c);  % s = a/b/c when idx = 0/1/2
            %
            % See also sig.Signal/cond, sig.Signal/indexOfFirst
            net = this.Node.Net;
            option_nodes = this.Node.from(varargin{:});
            nodes  = [this.Node, option_nodes];
            n_opts = numel(option_nodes);
            fmt = ['%s.selectFrom([ ' strjoin(repmat({'%s'}, 1, n_opts), ' ; ') ' ])'];
            s = sig.Signal(net.addNode(nodes, sig.OpCode.select_from, false));
            s.Node.FormatSpec    = fmt;
            s.Node.DisplayInputs = nodes;
        end

        function f = indexOfFirst(varargin)
            % INDEXOFFIRST  0-based index of first truthy signal.
            %
            %   f = indexOfFirst(pred0, pred1, ...) returns a signal that
            %   fires the 0-based index of the first input whose latest
            %   value is truthy.  If no input is truthy, no output is
            %   produced.  Used internally by cond/iff.
            %
            % Inputs:
            %   pred0..predN (sig.Signal|scalar) - predicate signals
            %
            % Outputs:
            %   f (sig.Signal) - 0-based index of first truthy pred, or
            %                    no output when all predicates are falsy
            %
            % See also sig.Signal/cond, sig.Signal/selectFrom
            refNode = [];
            for k = 1:numel(varargin)
                if isa(varargin{k}, 'sig.Signal')
                    refNode = varargin{k}.Node; break;
                end
            end
            assert(~isempty(refNode), 'sig:noNet', ...
                'indexOfFirst: no sig.Signal found in inputs.');
            nodes = refNode.from(varargin{:});
            net   = refNode.Net;
            n     = numel(nodes);
            fmt   = ['indexOfFirst([ ' strjoin(repmat({'%s'}, 1, n), ' ; ') ' ])'];
            f = sig.Signal(net.addNode(nodes, sig.OpCode.index_of_first, false));
            f.Node.FormatSpec    = fmt;
            f.Node.DisplayInputs = nodes;
        end

        function c = cond(this, value1, varargin)
            % COND  Conditional signal: first value whose predicate is truthy.
            %
            %   c = cond(pred1, val1, pred2, val2, ...) returns a signal
            %   that fires the value corresponding to the first truthy
            %   predicate.  Predicates are re-evaluated whenever any fires.
            %   If no predicate is truthy, no output is produced.
            %
            % Inputs:
            %   pred1, pred2, ... (sig.Signal) - gate signals evaluated
            %                                    in order
            %   val1,  val2,  ... (sig.Signal|any) - values to select
            %
            % Outputs:
            %   c (sig.Signal) - fires the value paired with the first
            %                    truthy predicate
            %
            % Examples:
            %   c = cond(x > 0, posVal, x < 0, negVal);
            %   c = cond(flag, onSig);   % fires onSig only while flag truthy
            %
            % See also sig.Signal/iff, sig.Signal/selectFrom,
            %          sig.Signal/indexOfFirst
            preds = [{this}, varargin(1:2:end)];
            vals  = [{value1}, varargin(2:2:end)];
            assert(numel(preds) == numel(vals), 'sig:cond:mismatch', ...
                'cond: number of predicates must equal number of values.');
            nc = numel(preds);

            firstTrue = indexOfFirst(preds{:});
            c         = firstTrue.selectFrom(vals{:});

            % DisplayInputs: interleave value and predicate nodes so the
            % format string 'cond( %s if %s ; … )' receives them in order.
            val_nodes  = c.Node.Inputs(2:end);        % skip firstTrue.Node
            pred_nodes = firstTrue.Node.Inputs;
            interleave = reshape([1:nc; nc+(1:nc)], 1, []);
            all_display = [val_nodes, pred_nodes];
            c.Node.DisplayInputs = all_display(interleave);
            c.Node.FormatSpec = ...
                ['cond( ' strjoin(repmat({'%s if %s'}, 1, nc), ' ; ') ' )'];
        end

        function r = iff(this, trueVal, falseVal)
            % IFF  Binary conditional: trueVal when pred truthy, else falseVal.
            %
            %   r = iff(pred, trueVal, falseVal) is equivalent to
            %   cond(pred, trueVal, true, falseVal): fires trueVal while
            %   pred is truthy, falseVal otherwise.
            %
            %   r = iff(pred, trueVal) fires trueVal whenever pred is truthy
            %   and produces no output when pred is falsy.
            %
            % Inputs:
            %   this     (sig.Signal) - predicate signal
            %   trueVal  (sig.Signal|any) - value when pred is truthy
            %   falseVal (sig.Signal|any) - value when pred is falsy
            %                               (optional; no output if omitted)
            %
            % Outputs:
            %   r (sig.Signal) - conditional output
            %
            % Examples:
            %   reward = correct.iff(bigReward, smallReward);
            %   active = running.iff(speed);  % fires speed only while running
            %
            % See also sig.Signal/cond, sig.Signal/keepWhen
            if nargin > 2
                r = cond(this, trueVal, true, falseVal);
            else
                r = cond(this, trueVal);
            end
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
