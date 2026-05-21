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

            net = this.Node.Net;
            if isa(f, 'function_handle')
                m = sig.Signal(net.addNode(this.Node, sig.OpCode.map_op, false, f));
                if nargin < 3; formatSpec = sprintf('%%s.map(%s)', toStr(f)); end
                m.Node.FormatSpec = formatSpec;
            else
                % Constant or signal: f_node holds the value to sample when this fires.
                f_node = this.Node.from(f);
                nodes = [this.Node, f_node];
                % No callable: map_op samples inputs[1] when inputs[0] fires.
                m = sig.Signal(net.addNode(nodes, sig.OpCode.map_op, false));
                if nargin < 3; formatSpec = '%s.map(%s)'; end
                m.Node.FormatSpec = formatSpec;
            end
        end

        function m = map2(sig1, sig2, f, varargin)
        % map2  New signal = f(sig1, sig2) whenever either fires.
        %   Either argument may be a constant — it is wrapped automatically.
        %   Note: MATLAB may dispatch here with sig1 as a numeric constant
        %   (e.g., 3 + signal) due to class-precedence rules.
            m = mapn(sig1, sig2, f, varargin{:});
        end

        function varargout = mapn(varargin)
            % mapn  New signal(s) by applying f to N input signals/constants.
            %   Call as:  out = s1.mapn(s2, ..., sN, f)
            %          or: out = mapn(s1, s2, ..., sN, f)   (MATLAB dispatch)
            %   f is always the last argument; all preceding args are inputs.
            %   Multi-output: [X, Y] = a.mapn(b, @meshgrid)
            % FIXME Format specs all wrong
            if isa(varargin{end}, 'function_handle')
                [rawInputs{1:nargin-1}, f] = varargin{:};
                formatSpec = sprintf(['mapn(' repmat('%%s, ', 1, numel(rawInputs)) '%s)'], toStr(f));
            else
                [rawInputs{1:nargin-2}, f, formatSpec] = varargin{:};
            end
            [nodes, net] = sig.Node.from(rawInputs{:});
            nout   = max(1, nargout);

            if nout == 1
                varargout{1} = sig.Signal(net.addNode(nodes, sig.OpCode.mapn_op, false, f));
                varargout{1}.Node.FormatSpec = formatSpec;
            else
                % Pack all outputs into a cell, then unpack per output.
                pack_f = @(varargin) pack_outputs(f, nout, varargin{:});
                packNode = net.addNode(nodes, sig.OpCode.mapn_op, false, pack_f);
                packNode.FormatSpec = formatSpec;
                packNode.DisplayInputs = nodes;
                packSig = sig.Signal(packNode);
                pack_name = packNode.Name;
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
            if isa(criterion, 'sig.Signal') || isa(criterion, 'sig.Node')
                nodes    = this.Node.from(this, criterion);
                transFcn = @(values, states) sig.transfer.filter(values, states, f);
                s = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
            else
                pred = @(x) isequal(f(x), criterion);
                s = sig.Signal(net.addNode(this.Node, sig.OpCode.filter_op, false, pred));
            end
            s.Node.DisplayInputs = s.Node.Inputs(1); % Don't display criterion
            s.Node.FormatSpec = sprintf('%%s.filter(%s)', toStr(f));
        end

        function s = scan(this, f, seed, varargin)
        % scan  Running fold: acc = f(acc, new_value).
        %   seed — initial accumulator value, or a signal that resets it.
        %   'pars' — optional parameter signals (non-triggering, sampled on update).
        %     Usage: s = sig.Signal(...).scan(f, seed, 'pars', p1, p2, ...)
            pars = {};
            idx = 1;
            while idx <= numel(varargin)
                if strcmp(varargin{idx}, 'pars')
                    idx = idx + 1;
                    while idx <= numel(varargin)
                        pars{end+1} = varargin{idx};
                        idx = idx + 1;
                    end
                    break;
                end
                idx = idx + 1;
            end
            all_inputs = [{this, seed}, pars];
            nodes = this.Node.from(all_inputs{:});
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
            out = sig.Signal(node);
        end

        function s = at(what, when)
            % AT  Sample this signal's value whenever 'when' fires true.
            %
            %   out = at(what, when) returns a dependent signal that takes the
            %   latest value of 'what' at the moment 'when' fires with a truthy
            %   value.  The output fires in response to 'when' updating, not
            %   'what' — unlike keepWhen, posting a new value to 'what' alone
            %   does not cause output to fire.
            %
            % Inputs:
            %   what (sig.Signal) - the signal whose value to sample
            %   when (sig.Signal) - the gate signal; output fires each time
            %                       this updates with a truthy value
            %
            % Outputs:
            %   s (sig.Signal) - fires with the current value of 'what'
            %                      whenever 'when' fires truthy
            %
            % Examples:
            %   x_on_press = x.at(keyboard);  % sample x on each key press
            %   % Equivalent using then:
            %   x_on_press = keyboard.then(x);
            %
            % See also sig.Signal/then, sig.Signal/keepWhen
            [inputs, net] = sig.Node.from(what, when);
            s = sig.Signal(net.addNode(inputs, sig.OpCode.at_op, false));
            s.Node.FormatSpec = '%s.at(%s)';
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
            [inputs, net] = sig.Node.from(this, what);
            out = sig.Signal(net.addNode(inputs, sig.OpCode.at_op, false));
            out.Node.FormatSpec = '%s.then(%s)';
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

            [inputs, net] = sig.Node.from(this, when);
            s = sig.Signal(net.addNode(inputs, sig.OpCode.keep_when, false));
            s.Node.FormatSpec = '%s.keepWhen(%s)';
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
            [inputs, net] = sig.Node.from(this, release);
            out = sig.Signal(net.addNode(inputs, sig.OpCode.latch, false));
            out.Node.FormatSpec = '%s.to(%s)';
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
            armed = this.to(release);
            not_armed = ~armed;
            true_node = net.rootNode(true);
            tr = sig.Signal(net.addNode([true_node, not_armed.Node], sig.OpCode.at_op, false));
            tr.Node.FormatSpec    = '%s.setTrigger(%s)';
            tr.Node.DisplayInputs = [this.Node, release_node];
        end

        function tr = setEpochTrigger(this, t, x, threshold)
            % SETEPOCH TRIGGER  Fire when x has been stable for a full epoch.
            %
            %   tr = duration.setEpochTrigger(t, x) fires true once when
            %   time t has advanced by at least duration since x last changed.
            %   Any x update that differs from x_ref (the value at epoch start)
            %   by more than threshold resets the countdown.  Fires false when
            %   the epoch resets.  No output until x fires at least once.
            %
            %   tr = duration.setEpochTrigger(t, x, threshold) uses a custom
            %   threshold for what counts as a significant x change (default 0:
            %   any distinct value resets; Inf: only the first x post starts the
            %   epoch and subsequent x updates never reset it).
            %
            % Inputs:
            %   this      (sig.Signal) - epoch duration
            %   t         (sig.Signal) - absolute time (monotonically increasing)
            %   x         (sig.Signal) - position/state whose changes reset the epoch
            %   threshold (scalar, optional) - minimum |x - x_ref| to reset (default 0)
            %
            % Outputs:
            %   tr (sig.Signal) - logical; fires true when epoch elapses, false
            %                     when x resets the epoch
            %
            % See also sig.Signal/setTrigger, sig.Signal/delta
            if nargin < 4; threshold = 0; end

            % Track x_ref: x value at the start of the current epoch.
            % State starts as NaN (no epoch yet).  Updates to x_new when
            % |x_new - x_ref| > threshold (or on the very first x post).
            th = threshold;
            x_ref_sig = x.scan( ...
                @(x_new, x_ref) epoch_x_ref_update(x_new, x_ref, th), NaN);

            % epoch_reset fires 'duration' whenever a new epoch starts.
            epoch_reset = x_ref_sig.skipRepeats().map(this);

            % Countdown: reset to duration on epoch start; decrement each t step.
            remaining = t.delta().scan(@(dt, rem) rem - dt, epoch_reset);

            % Fire when countdown expires; suppress repeated fires in same state.
            expired = remaining <= 0;
            tr = expired.skipRepeats();

            % Name: Δx/Δt < threshold s.t. Δt = duration
            % FormatSpec has 4 %s: x-name, t-name, t-name, duration-name
            tr.Node.FormatSpec    = sprintf([char(916), '%%s/', char(916), ...
                '%%s < %s s.t. ', char(916), '%%s = %%s'], num2str(threshold));
            tr.Node.DisplayInputs = [x.Node, t.Node, t.Node, this.Node];
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
            out.Node.FormatSpec = '%s.skipRepeats()';
        end

        function out = delta(this)
            % DELTA  Difference between consecutive values.
            %
            %   out = this.delta() fires this(t) - this(t-1) whenever 'this'
            %   updates.  No output is produced until at least two values have
            %   been posted.
            %
            % Outputs:
            %   out (sig.Signal) - fires the step difference on each update
            %
            % See also sig.Signal/lag, sig.Signal/scan
            out = this - this.lag(1);
            out.Node.FormatSpec = '%s.delta()';
            out.Node.DisplayInputs = this.Node;
        end

        function d = delay(this, period)
            % DELAY Update with `this` value after a period
            %
            %   d = this.delay(period) updates with the value of `this`
            %   after a delay of `period` seconds.
            %
            % Inputs:
            %   this (sig.Signal) - The signal who's value to take after
            %     the delay period.
            %   period (sig.Signal|double) - The delay period in seconds.
            %
            % Outputs:
            %   d (sig.Signal) - a signal that updates after a delay
            %
            % Examples:
            %   d = x.delay(5); % d updates with value of x after 5 seconds
            %   d = x.delay(delaySignal); % delay determined by another signal
            %
            % See also sig.Signal/lag, sig.Signal/identity

            net = this.Node.Net;

            % Create a scheduler signal that combines the value and delay
            % into a {value, delay} packet using the schedule transfer function
            nodes = this.Node.from(this, period);
            transFcn = @(values, states) sig.transfer.schedule(values, states, []);
            scheduler = sig.Signal(net.addNode(nodes, sig.OpCode.function_op, false, transFcn));
            scheduler.Node.FormatSpec = '%s.schedule(%s)';

            % Create an OriginSignal to output delayed values
            d = net.origin();

            % Attach a listener that posts values after the delay
            % The listener function is called with the scheduler packet {value, delay}
            delayedPost = scheduler.onValue(@(packet) d.delayedPost(packet));

            % Derive a dependent (i.e. non-origin) signal to obscure the
            % origin signal and its post methods
            d = identity(d);  % a standard signal is returned
            d.Node.FormatSpec = '%s.delay(%s)';
            d.Node.DisplayInputs = scheduler.Node.DisplayInputs;

            % Store the listener to prevent garbage collection
            d.Node.Listeners = [d.Node.Listeners delayedPost];
        end

        function out = lag(this, n)
            % LAG  Signal delayed by n updates.
            %
            %   out = this.lag(n) fires the value that 'this' held n updates ago.
            %   No output is produced until at least n+1 values have been posted.
            %   lag(0) is equivalent to identity.
            %
            % Inputs:
            %   this (sig.Signal) - input signal
            %   n    (non-negative integer scalar) - number of steps to delay
            %
            % Outputs:
            %   out (sig.Signal) - fires this(t-n) whenever this(t) fires and
            %                      the internal buffer has at least n+1 elements
            %
            % See also sig.Signal/bufferUpTo, sig.Signal/identity
            bup = this.bufferUpTo(n + 1);
            out = bup.keepWhen(bup.nElems() == n + 1).map(@(v) v(1));
            out.Node.FormatSpec = sprintf('%%s.lag(%d)', n);
            out.Node.DisplayInputs = this.Node;
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
            [inputs, net] = sig.Node.from(this, nSamples);
            if nargin > 2 && strcmpi(typeChange, 'cell')
                % Dummy callable signals cast mode to the C++ transfer block;
                % it is never invoked — its presence is the flag.
                castMarker = @(varargin) [];
                bup = sig.Signal(net.addNode(inputs, ...
                    sig.OpCode.buffer_up_to, false, castMarker));
            else
                bup = sig.Signal(net.addNode(inputs, ...
                    sig.OpCode.buffer_up_to, false));
            end
            bup.Node.FormatSpec    = '%s.bufferUpTo(%s)';
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
            [inputs, net] = sig.Node.from(varargin{:});
            m = sig.Signal(net.addNode(inputs, sig.OpCode.merge, false));
            n = numel(inputs);
            m.Node.FormatSpec = ['( ' strjoin(repmat({'%s'}, 1, n), ' ~ ') ' )'];
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
            [nodes, net] = sig.Node.from(varargin{:});
            n = numel(nodes);
            f = sig.Signal(net.addNode(nodes, sig.OpCode.index_of_first, false));
            f.Node.FormatSpec = ['indexOfFirst([ ' strjoin(repmat({'%s'}, 1, n), ' ; ') ' ])'];
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

        function h = output(this)
            % OUTPUT Display current value each update
            %   Prints the value of this Signal to the command window each time
            %   it updates.  Returns a listener handle which when cleared removes
            %   this callback.
            %
            % See also onValue
            h = onValue(this, @disp);
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

        %% Overloaded MATLAB Methods

        function y = vertcat(varargin)
            % New signal carrying the vertical concatenation of signals
            formatSpec = ['[' strJoin(repmat({'%s'}, 1, nargin), '; ') ']'];
            y = mapn(varargin{:}, @vertcat, formatSpec);
        end

        function y = horzcat(varargin)
            % New signal carrying the horizontal concatenation of signals
            formatSpec = ['[' strJoin(repmat({'%s'}, 1, nargin), ' ') ']'];
            y = mapn(varargin{:}, @horzcat, formatSpec);
        end

        function c = ge(a, b)
            % New signal carrying the current inequality (>=) between signals
            % The function handle fcn is attached as a fallback callable,
            % invoked only when the C++ traits throw signals::TypeError
            % (i.e. for non-basic types).
            [inputs, net] = sig.Node.from(a, b);
            c = sig.Signal(net.addNode(inputs, sig.OpCode.ge_op, false, @ge));
            c.Node.FormatSpec = '%s >= %s';
        end

        function c = gt(a, b)
            % New signal carrying the current inequality (>) between signals
            [inputs, net] = sig.Node.from(a, b);
            c = sig.Signal(net.addNode(inputs, sig.OpCode.gt_op, false, @gt));
            c.Node.FormatSpec = '%s > %s';
        end

        function c = le(a, b)
            % New signal carrying the current inequality (<=) between signals
            [inputs, net] = sig.Node.from(a, b);
            c = sig.Signal(net.addNode(inputs, sig.OpCode.le_op, false, @le));
            c.Node.FormatSpec = '%s <= %s';
        end

        function c = lt(a, b)
            % New signal carrying the current inequality (<) between signals
            [inputs, net] = sig.Node.from(a, b);
            c = sig.Signal(net.addNode(inputs, sig.OpCode.lt_op, false, @lt));
            c.Node.FormatSpec = '%s < %s';
        end

        function c = ne(a, b, handleComparison)
            % New signal carrying the current non-equality (~=) between signals
            if nargin < 3 || ~handleComparison
                c = map2(a, b, @ne, '%s ~= %s');
            else
                c = ne@handle(a, b);
            end
        end

        function x = num2str(numSig, precision)
            % New signal carrying numeric-to-charecter converted array of the
            % input signal
            narginchk(1,2)
            if nargin == 1
                x = map(numSig, @num2str, 'num2str(%s)');
            else
                x = map2(numSig, precision, @num2str, 'num2str(%s)');
            end
        end

        function b = round(a,N,type)
            % New signals carrying the result of rounding 'a' to 'N' digits
            if nargin < 2
                b = map(a, @round, 'round(%s)');
            elseif nargin < 3
                b = map2(a, N, @round, 'round(%s) to %s digits');
            else
                b = mapn(a, N, type, @round, 'round(%s) to %s digits by %s');
            end
        end

        function b = sum(a, dim)
            % New signal carrying the sum of all array elements in 'a' across
            % dimention 'dim'
            if nargin < 2
                b = map(a, @sum, 'sum(%s)');
            else
                b = map2(a, dim, @sum, 'sum(%s) over dim %s');
            end
        end

        function varargout = min(A,B,dim)
            % [M,I] = min(A,B,dim) New signal carrying the min value of inputs.
            if nargin < 2
                [varargout{1:nargout}] = mapn(A, @min, 'min(%s)');
            elseif nargin < 3
                [varargout{1:nargout}] = mapn(A, B, @min, 'min(%s,%s)');
            else
                [varargout{1:nargout}] = mapn(A, B, dim, @min, 'min(%s) over dim %s');
                for i = 1:nargout; varargout{i}.Node.DisplayInputs(2) = []; end
            end
        end

        function varargout = max(A,B,dim)
            % [M,I] = max(A,B,dim) New signal carrying the max value of its
            % inputs
            if nargin < 2
                [varargout{1:nargout}] = mapn(A, @max, 'max(%s)');
            elseif nargin < 3
                [varargout{1:nargout}] = mapn(A, B, @max, 'max(%s,%s)');
            else
                [varargout{1:nargout}] = mapn(A, B, dim, @max, 'max(%s) over dim %s');
                for i = 1:nargout; varargout{i}.Node.DisplayInputs(2) = []; end
            end
        end

        function b = rot90(a, k)
            % New signal carrying 'a' rotated 90 degrees counter-clockwise 'k'
            % times
            if nargin < 2
                b = map(a, @rot90, 'rot90(%s)');
            else
                b = map2(a, k, @rot90, 'rot90(%s) %s times');
            end
        end

        function b = any(a, dim)
            if nargin < 2
                b = map(a, @any, 'any(%s)');
            else
                b = map2(a, dim, @any, 'any(%s) over dim %s');
            end
        end

        function b = all(a, dim)
            if nargin < 2
                b = map(a, @all, 'all(%s)');
            else
                b = map2(a, dim, @all, 'all(%s) over dim %s');
            end
        end

        function a = colon(i,j,k)
            if nargin < 3
                a = map2(i,j, @colon, '%s : %s');
            else
                a = mapn(i,j,k, @colon, '%s : %s : %s');
            end
        end
      
        % % =================================================================
        % % Operator overloads — all implemented via map / map2 / mapn
        % % =================================================================
        % 
        function b = floor(a),     b = a.map(@floor, 'floor(%s)');         end
        function b = abs(a),       b = a.map(@abs, '|%s|');                end
        function b = sign(a),      b = a.map(@sign, 'sgn(%s)');            end
        function b = sin(a),       b = a.map(@sin, 'sin(%s)');             end
        function b = cos(a),       b = a.map(@cos, 'cos(%s)');             end
        function b = uminus(a),    b = a.map(@uminus, '-%s');              end
        function b = not(a),       b = a.map(@not, '~%s');                 end
        function b = exp(a),       b = a.map(@exp, 'exp(%s)');             end
        function b = sqrt(a),      b = a.map(@sqrt, [char(8730), '(%s)']); end
        function b = erf(a),       b = a.map(@erf, 'erf(%s)');             end
        function b = transpose(a), b = a.map(@transpose, '%s''');          end
        function b = fliplr(a),    b = a.map(@fliplr, 'fliplr(%s)');      end
        function b = flipud(a),    b = a.map(@flipud, 'flipud(%s)');      end
        function b = str2num(a),   b = a.map(@str2num, 'str2num(%s)'); end
        
        function c = plus(a, b),    c = map2(a, b, @plus, '(%s + %s)');    end
        function c = minus(a, b),   c = map2(a, b, @minus, '(%s - %s)');   end
        function c = times(a, b),   c = map2(a, b, @times, '%s.*%s');   end
        function c = mtimes(a, b),  c = map2(a, b, @mtimes, '%s*%s');  end
        function c = rdivide(a, b), c = map2(a, b, @rdivide, '%s./%s'); end
        function c = mrdivide(a,b), c = map2(a, b, @mrdivide, '%s/%s');end
        function c = mpower(a, b),  c = map2(a, b, @mpower, '%s^%s');  end
        function c = power(a, b),   c = map2(a, b, @power, '%s.^%s');   end
        function c = mod(a, b),     c = map2(a, b, @mod, '%s %% %s');           end
        function c = strcmp(a, b),  c = map2(a, b, @strcmp, 'strcmp(%s, %s)');  end
        function c = and(a, b),     c = map2(a, b, @and, '%s & %s');     end
        function c = or(a, b),      c = map2(a, b, @or, '%s | %s');      end

        function c = eq(a, b, handleComparison)
        % eq  Signal equality, or handle identity when handleComparison=true.
            if nargin >= 3 && handleComparison
                c = eq@handle(a, b);
            else
                [inputs, net] = sig.Node.from(a, b);
                c = sig.Signal(net.addNode(inputs, sig.OpCode.eq_op, false, @eq));
                c.Node.FormatSpec = '%s == %s';
            end
        end

        function b = sz(a, dim)
        % sz  New signal whose value is size(this_value[, dim]).
            if nargin < 2, b = a.map(@size);
            else,          b = map2(a, dim, @size); end
        end

        function [varargout] = subsref(this, s)
        % subsref  () subscripts create derived signals; others use builtin.
            if strcmp(s(1).type, '()')
                subs = s(1).subs;

                % Use transfer function for consistent handling
                net = this.Node.Net;

                % Build input nodes, excluding sig.End objects.
                % Only pass non-sig.End subscripts to from()
                subs_for_nodes = {};
                for k = 1:numel(subs)
                    if ~isa(subs{k}, 'sig.End')
                        subs_for_nodes{end+1} = subs{k};
                    end
                end

                inpNodes = this.Node.from(this, subs_for_nodes{:});

                % Create a wrapper that passes subs directly
                subsref_with_subs = @(values, states) sig.transfer.subsref_direct(values, states, subs);
                outNode = net.addNode(inpNodes, sig.OpCode.function_op, false, subsref_with_subs);

                % Format the display name
                sigNames = cell(numel(subs), 1);
                displayNodes = this.Node;  % start with the array node
                nodeIdx = 2;  % track which node in inpNodes we're using

                for k = 1:numel(subs)
                    if isa(subs{k}, 'sig.Signal')
                        sigNames{k} = '%s';  % placeholder for signal name
                        displayNodes = [displayNodes, inpNodes(nodeIdx)];
                        nodeIdx = nodeIdx + 1;
                    elseif isa(subs{k}, 'sig.End')
                        sigNames{k} = 'end';
                        % Don't add to displayNodes for sig.End objects
                    elseif isvector(subs{k}) && isrow(subs{k}) && numel(subs{k}) > 1
                        % For ranges/vectors, show individual elements
                        numStrs = cellstr(num2str(subs{k}(:)));
                        numStrs = cellfun(@strtrim, numStrs, 'UniformOutput', false);
                        sigNames{k} = strJoin(numStrs, '   ');
                        nodeIdx = nodeIdx + 1;  % skip the root node
                    else
                        sigNames{k} = toStr(subs{k});
                        nodeIdx = nodeIdx + 1;  % skip the root node
                    end
                end
                inpform = strJoin(sigNames, ' ');
                outNode.FormatSpec = ['%s(' inpform ')'];
                outNode.DisplayInputs = displayNodes;

                out = sig.Signal(outNode);

                if length(s) > 1
                    [varargout{1:nargout}] = subsref(out, s(2:end));
                else
                    varargout = {out};
                end
            else
                [varargout{1:nargout}] = builtin('subsref', this, s);
            end
        end

        function e = end(~, k, n)
        % end  Support MATLAB's end keyword in signal subscripting
        %   This method is called automatically by MATLAB when 'end' is used
        %   in subscripts. It returns a sig.End object that will be resolved
        %   when the signal's value is known.
        %
        %   Example:
        %     last = signal(end)        % last element
        %     range = signal(end-5:end) % last 6 elements
            e = sig.End(k, n);
        end
    end

end


function x_ref = epoch_x_ref_update(x_new, x_ref, threshold)
% Update x_ref for setEpochTrigger: start a new epoch when the position has
% moved more than threshold from the epoch-start reference.
if isnan(x_ref) || abs(x_new - x_ref) > threshold
    x_ref = x_new;
end
end
