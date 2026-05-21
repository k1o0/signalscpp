classdef Signals_test < matlab.unittest.TestCase
  properties
    net
    A
    B
    C
  end

  methods (TestClassSetup)
    function createNetwork(testCase)
      testCase.net = sig.Net;
      testCase.addTeardown(@delete, testCase.net)
    end
  end

  methods (TestMethodSetup)
    function setupInputSignals(testCase)
      testCase.A = testCase.net.origin('a');
      testCase.B = testCase.net.origin('b');
      testCase.C = testCase.net.origin('c');

      testCase.addTeardown(@delete, testCase.A)
      testCase.addTeardown(@delete, testCase.B)
      testCase.addTeardown(@delete, testCase.C)
    end
  end

  methods (Test)
    function test_setEpochTrigger(testCase)
      % Tests for setEpochTrigger: fires when t advances >= duration since x last changed
      [dur_sig, t_sig, x_sig] = deal(testCase.A, testCase.B, testCase.C);

      dur = 5;
      dur_sig.post(dur);
      tr = dur_sig.setEpochTrigger(t_sig, x_sig);  % default threshold = 0

      % Name contains Δ and the < threshold s.t. Δ structure
      testCase.verifyMatches(tr.Name, ...
        sprintf('%1$s\\w+/%1$s\\w+ < \\S+ s\\.t\\. %1$s\\w+ = \\w+', char(916)), ...
        'Unexpected Name')

      % No value before x fires (epoch not yet started)
      testCase.verifyEmpty(tr.Node.Value, 'Expected tr empty before x fires')

      % x fires: epoch starts, x_ref = 1.0, remaining = dur, tr = false
      x_sig.post(1.0);
      testCase.verifyFalse(tr.Node.Value, 'Expected tr false after x fires')

      % t fires for the first time (no delta yet)
      t_sig.post(0);
      testCase.verifyFalse(tr.Node.Value, 'Expected tr false after first t post')

      % t advances but not enough (delta = 3 < dur = 5; remaining = 2)
      t_sig.post(3);
      testCase.verifyFalse(tr.Node.Value, 'Expected tr false with insufficient elapsed time')

      % t advances enough: delta = 3, remaining = 2-3 = -1 → tr = true
      t_sig.post(6);
      testCase.verifyTrue(tr.Node.Value, 'Expected tr true when epoch elapses')

      % Further t while already expired: skipRepeats suppresses
      affected = testCase.net.transact(t_sig, 7);
      testCase.verifyFalse(ismember(tr.Node.Id, affected), ...
        'Expected tr not in affected after epoch already expired')
      testCase.net.apply(affected);

      % x fires with a different value (threshold=0 default: any change resets)
      x_sig.post(2.0);  % |2.0 - 1.0| = 1.0 > 0 → epoch resets
      testCase.verifyFalse(tr.Node.Value, 'Expected tr false after x resets epoch')

      % t delta = 1 (7→8): remaining = 5-1 = 4
      t_sig.post(8);
      testCase.verifyFalse(tr.Node.Value, 'Expected tr false with insufficient time after reset')

      % t delta = 5 (8→13): remaining = 4-5 = -1 → tr = true again
      t_sig.post(13);
      testCase.verifyTrue(tr.Node.Value, 'Expected tr true after second epoch elapses')

      % ── Finite threshold: small x changes do not reset the epoch ────────────
      dur_sig2 = testCase.net.origin('dur2');
      t_sig2   = testCase.net.origin('t2');
      x_sig2   = testCase.net.origin('x2');
      testCase.addTeardown(@delete, dur_sig2, t_sig2, x_sig2)

      dur_sig2.post(3);
      tr2 = dur_sig2.setEpochTrigger(t_sig2, x_sig2, 0.5);

      % Epoch starts; x_ref = 1.0
      x_sig2.post(1.0);
      t_sig2.post(0);

      % Small x changes (within threshold) do not reset the countdown
      x_sig2.post(1.3);   % |1.3-1.0| = 0.3 <= 0.5: no reset
      t_sig2.post(2);     % delta=2, remaining=3-2=1
      x_sig2.post(1.4);   % |1.4-1.0| = 0.4 <= 0.5: no reset
      t_sig2.post(3);     % delta=1, remaining=1-1=0 → 0<=0 → true
      testCase.verifyTrue(tr2.Node.Value, 'Expected tr2 true: small x moves within threshold')

      % Large x change (exceeds threshold) resets the epoch → tr2 = false
      x_sig2.post(2.5);   % |2.5-1.0| = 1.5 > 0.5: epoch resets, x_ref=2.5, remaining=3
      testCase.verifyFalse(tr2.Node.Value, 'Expected tr2 false after large x resets epoch')

      % Epoch elapses again after the reset
      t_sig2.post(5);     % delta=2 (3→5), remaining=3-2=1
      t_sig2.post(7);     % delta=2 (5→7), remaining=1-2=-1 → true
      testCase.verifyTrue(tr2.Node.Value, 'Expected tr2 true after epoch elapses post-reset')
    end

    function test_delta(testCase)
      % Tests for delta: fires this(t) - this(t-1)
      a = testCase.A;
      d = a.delta();
      testCase.verifyMatches(d.Name, '\w+\.delta\(\)', 'Unexpected Name')

      % No output after first post (need a previous value)
      v1 = rand;
      a.post(v1);
      testCase.verifyEmpty(d.Node.Value, 'Expected d empty after first post')

      % Second post — fires v2 - v1
      v2 = rand;
      a.post(v2);
      testCase.verifyEqual(d.Node.Value, v2 - v1, 'Expected d = v2 - v1')

      % Third post — fires v3 - v2
      v3 = rand;
      a.post(v3);
      testCase.verifyEqual(d.Node.Value, v3 - v2, 'Expected d = v3 - v2')
    end

    function test_lag(testCase)
      % Tests for lag: fires the value from n updates ago
      [a, b] = deal(testCase.A, testCase.B);

      % lag(1): fires the value from 1 step back
      l1 = a.lag(1);
      testCase.verifyMatches(l1.Name, '\w+\.lag\(\d+\)', 'Unexpected Name')

      % No output after only 1 post (need n+1=2 posts)
      v1 = rand;
      a.post(v1);
      testCase.verifyEmpty(l1.Node.Value, 'Expected l1 empty after first post')

      % Second post — l1 fires v1 (the value from 1 step ago)
      v2 = rand;
      a.post(v2);
      testCase.verifyEqual(l1.Node.Value, v1, 'Expected l1 = v1 after second post')

      % Third post — l1 fires v2
      v3 = rand;
      a.post(v3);
      testCase.verifyEqual(l1.Node.Value, v2, 'Expected l1 = v2 after third post')

      % lag(2): fires the value from 2 steps back
      l2 = b.lag(2);
      w1 = rand; b.post(w1);
      testCase.verifyEmpty(l2.Node.Value, 'Expected l2 empty after 1 post')
      w2 = rand; b.post(w2);
      testCase.verifyEmpty(l2.Node.Value, 'Expected l2 empty after 2 posts')
      w3 = rand; b.post(w3);
      testCase.verifyEqual(l2.Node.Value, w1, 'Expected l2 = w1 after 3 posts')
      w4 = rand; b.post(w4);
      testCase.verifyEqual(l2.Node.Value, w2, 'Expected l2 = w2 after 4 posts')
    end

    function test_skipRepeats(testCase)
      % Tests for skipRepeats: passes new values, suppresses duplicates
      a = testCase.A;
      s = a.skipRepeats();
      testCase.verifyMatches(s.Name, '\w+\.skipRepeats\(\)', 'Unexpected Name')

      % Starts empty before any post
      testCase.verifyEmpty(s.Node.Value, 'Expected s empty before any post')

      % First value always passes through (no prior value to compare)
      v1 = rand;
      a.post(v1);
      testCase.verifyEqual(s.Node.Value, v1, 'Expected s to fire on first post')

      % Same double value is suppressed
      affected = testCase.net.transact(a, v1);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Expected s not in affected when same double posted twice')
      testCase.net.apply(affected);
      testCase.verifyEqual(s.Node.Value, v1, 'Expected s unchanged after repeat')

      % Different double value passes through
      v2 = rand;
      a.post(v2);
      testCase.verifyEqual(s.Node.Value, v2, 'Expected s to fire on different double')

      % Non-double (string) — isequal fallback in C++
      a.post('hello');
      testCase.verifyEqual(s.Node.Value, 'hello', 'Expected s to fire on first string post')

      % Same string is suppressed
      affected = testCase.net.transact(a, 'hello');
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Expected s not in affected when same string posted twice')
      testCase.net.apply(affected);

      % Different string passes through
      a.post('world');
      testCase.verifyEqual(s.Node.Value, 'world', 'Expected s to fire on different string')
    end

    function test_bufferUpTo(testCase)
      % Tests for bufferUpTo: default = typed double; 'cell' option = cell array
      [a, b, c] = deal(testCase.A, testCase.B, testCase.C);

      % ── Default (typed double) path ───────────────────────────────────────
      bup = a.bufferUpTo(3);
      testCase.verifyMatches(bup.Name, '\w+\.bufferUpTo\(\d+\)', 'Unexpected Name')

      v1 = rand;
      a.post(v1)
      testCase.verifyEqual(bup.Node.Value, v1, 'Expected scalar double after first post')

      v2 = rand;
      a.post(v2)
      testCase.verifyEqual(bup.Node.Value, [v1, v2], 'Expected 1x2 double after second post')

      v3 = rand;
      a.post(v3)
      testCase.verifyEqual(bup.Node.Value, [v1, v2, v3], 'Expected 1x3 double when full')

      v4 = rand;
      a.post(v4)
      testCase.verifyEqual(bup.Node.Value, [v2, v3, v4], 'Expected trimmed 1x3 double after overflow')

      % Type change in strict (default) mode raises an error
      testCase.verifyError(@() a.post('x'), 'signals:runtimeError', ...
        'Expected error on type change in strict mode')

      % ── 'cell' option: mixed-type buffering ──────────────────────────────
      % Use signal c (independent of bup/a) so the strict-mode bup node doesn't
      % interfere by throwing before the cast-mode node is evaluated.
      bup2 = c.bufferUpTo(3, 'cell');

      c.post(1.0)
      testCase.verifyEqual(bup2.Node.Value, 1.0, 'Expected scalar double in cell-mode start')

      c.post(2.0)
      testCase.verifyEqual(bup2.Node.Value, [1.0, 2.0], 'Expected typed double before type change')

      c.post('hello')  % type change — should silently cast to cell
      val = bup2.Node.Value;
      testCase.verifyTrue(iscell(val), 'Expected cell array after type change')
      testCase.verifyEqual(numel(val), 3, 'Expected 3-element cell after type change')
      testCase.verifyEqual(val{end}, 'hello', 'Last cell should be the string item')

      % ── nSamples as a Signal ─────────────────────────────────────────────
      buff = a.bufferUpTo(b);
      testCase.verifyMatches(buff.Name, '\w+\.bufferUpTo\(\w+\)', 'Unexpected Name for signal nSamples')

      % No output until b (nSamples) has a value
      affected = testCase.net.transact(a.Node, rand);
      testCase.net.apply(affected);
      testCase.verifyFalse(ismember(buff.Node.Id, affected), ...
        'bufferUpTo should not fire before nSamples is defined')

      % After b fires, subsequent a posts accumulate as typed doubles
      n = 3;
      b.post(n)
      a.post(rand); a.post(rand); a.post(rand)
      testCase.verifyEqual(numel(buff.Node.Value), n, ...
        'Expected buffer length to equal nSamples after filling')
      testCase.verifyEqual(buff.Node.Value(end), a.Node.Value, ...
        'Last element should match most recent a value')

      % Shrinking nSamples trims buffer on next item post
      b.post(n - 1)
      a.post(rand)
      testCase.verifyEqual(numel(buff.Node.Value), n - 1, ...
        'Expected buffer to trim when nSamples decreases')
      testCase.verifyEqual(buff.Node.Value(end), a.Node.Value, ...
        'Last element should match most recent a value after trim')
    end

    function test_buffer(testCase)
      % Tests for buffer: fires only once nSamples double values accumulated
      a = testCase.A;
      n = 3;
      b = a.buffer(n);

      testCase.verifyMatches(b.Name, '\w+\.buffer\(\d+\)', 'Unexpected Name')

      % Buffer not yet full — b should not fire
      a.post(rand)
      testCase.verifyEmpty(b.Node.Value, 'buffer should not fire with < n samples')

      a.post(rand)
      testCase.verifyEmpty(b.Node.Value, 'buffer should not fire with < n samples')

      % Exactly n posts — buffer fires for the first time
      v = rand(1, n);
      arrayfun(@(x) a.post(x), v(1:end-2))  % 2 already posted; post n-2 more
      a.post(v(end-1)); a.post(v(end))
      testCase.verifyFalse(isempty(b.Node.Value), 'buffer should fire once n samples posted')
      testCase.verifyEqual(numel(b.Node.Value), n, 'buffer value should have exactly n elements')

      % Rolling: one more post still fires with n elements, oldest dropped
      vNext = rand;
      b_prev = b.Node.Value;
      a.post(vNext)
      testCase.verifyFalse(isempty(b.Node.Value), 'buffer should fire after n+1 posts')
      testCase.verifyEqual(numel(b.Node.Value), n, 'rolling buffer should keep exactly n elements')
      testCase.verifyEqual(b.Node.Value(end), vNext, 'last element should be newest value')
      testCase.verifyFalse(isequal(b.Node.Value, b_prev), 'rolling buffer should shift by one')
    end

    function test_filter(testCase)
      % Tests for filter method
      [a, b] = deal(testCase.A, testCase.B);
      f = a.filter(@ischar, b);

      % Test format specification
      testCase.verifyMatches(f.Name, '\w+\.filter\(@\w+\)', 'Unexpected Name')

      b.post(true) % Keep passed
      testCase.verifyEmpty(f.Node.Value, 'Unexpected update')

      % Test filtering
      a.post('c')
      testCase.verifyEqual(f.Node.Value, a.Node.Value, ...
        'Failed to update with the correct value')
      a.post(2)
      testCase.verifyNotEqual(f.Node.Value, a.Node.Value, ...
        'Failed to discard value')

      b.post(false) % Keep failed
      a.post(2)
      testCase.verifyEqual(f.Node.Value, a.Node.Value, ...
        'Failed to update with the correct value')
      a.post('c')
      testCase.verifyNotEqual(f.Node.Value, a.Node.Value, ...
        'Failed to discard value')

      % Test functions are char
      f = a.filter('~=2');
      a.post(0)
      testCase.verifyEqual(f.Node.Value, a.Node.Value, ...
        'Failed to discard value')
      a.post(2)
      testCase.verifyNotEqual(f.Node.Value, a.Node.Value, ...
        'Failed to update with the correct value')
    end

    function test_map(testCase)
      % Tests for map method
      [a, c] = deal(testCase.A, testCase.C);

      % Map through a MATLAB function
      b = a.map(@fliplr);
      arr = 1:3;
      a.post(arr)
      testCase.verifyEqual(b.Node.Value, fliplr(arr), ...
        'Unexpected output when mapping function')
      testCase.verifyMatches(b.Name, '\w+\.map\(@\w+\)', 'Unexpected Name')

      % Map to a constant (non-function-handle)
      v = rand;
      b = a.map(v);
      a.post(arr)
      testCase.verifyEqual(b.Node.Value, v, ...
        'Unexpected output when mapping constant')
      testCase.verifyMatches(b.Name, '\w+\.map\([\d\.]+\)', 'Unexpected Name')

      % Map one Signal to another (sample c whenever a fires)
      b = a.map(c);
      c.post(arr)
      testCase.verifyEmpty(b.Node.Value, ...
        'Expected dependent Signal to be empty before a fires')
      a.post(0)
      testCase.verifyEqual(b.Node.Value, arr, ...
        'Unexpected output when mapping Signal')
      testCase.verifyMatches(b.Name, '\w+\.map\(\w+\)', 'Unexpected Name')
    end

    function test_mapn(testCase)
      % Tests for mapn method
      [a, b] = deal(testCase.A, testCase.B);

      % Multi-output: both outputs correct, neither fires until all inputs set
      [X, Y] = a.mapn(b, @meshgrid);
      xx = 1:5; yy = 5:10;
      [expectedX, expectedY] = meshgrid(xx, yy);

      a.post(xx);
      testCase.verifyEmpty(X.Node.Value, 'X should be empty before b fires')
      testCase.verifyEmpty(Y.Node.Value, 'Y should be empty before b fires')

      b.post(yy);
      testCase.verifyTrue(isequal(X.Node.Value, expectedX), ...
        'X value incorrect after both inputs set')
      testCase.verifyTrue(isequal(Y.Node.Value, expectedY), ...
        'Y value incorrect after both inputs set')

      % Name properties
      testCase.verifyMatches(X.Name, 'mapn\(\w+, \w+, @meshgrid\)', 'Unexpected X Name')
      testCase.verifyMatches(Y.Name, '.*[2]', 'Unexpected Y Name')

      % Single-output fires when one input updates (using latest of other)
      s = a.mapn(b, @(x, y) x + y);
      a.post(3); b.post(7);
      testCase.verifyEqual(s.Node.Value, 10.0, 'mapn single output incorrect')
    end

    function test_merge(testCase)
      % Tests for merge method
      [a, b, c] = deal(testCase.A, testCase.B, testCase.C);

      m = merge(a, b, c);
      testCase.verifyMatches(m.Name, '\( \w+ ~ \w+ ~ \w+ \)', 'Unexpected Name')

      % Starts with no value
      testCase.verifyEmpty(m.Node.Value, 'Expected m empty before any input fires')

      % Each input independently updates m
      for sig_cell = {c, b, a, b}
        v = rand;
        sig_cell{1}.post(v);
        testCase.verifyEqual(m.Node.Value, v, 'Unexpected output using merge')
      end

      % Priority: when multiple inputs fire in the same transaction,
      % the earliest in the argument list wins (merge iterates inputs
      % and takes the first with a working value)
      v_a = rand;
      v_b = rand;
      affected_a = testCase.net.transact(a, v_a);
      affected_b = testCase.net.transact(b, v_b);
      testCase.net.apply(unique([affected_a(:); affected_b(:)]));
      testCase.verifyEqual(m.Node.Value, v_a, ...
        'Expected first input to win when multiple fire in same transaction')
    end

    function test_flatten(testCase)
      % Tests for flatten method
      [a, b, c] = deal(testCase.A, testCase.B, testCase.C);
      flat = a.flatten();

      % Test return on unset director — both a and flat should be empty
      testCase.verifyEqual(a.Node.Value, flat.Node.Value, ...
        'failed to retrieve director value')

      % Test flatten of signal with regular value
      val = rand;
      a.post(val)
      testCase.verifyEqual(a.Node.Value, flat.Node.Value, ...
        'failed to retrieve director value')
      testCase.verifyMatches(flat.Name, '\w+\.flatten()', 'Unexpected Name')

      % Test flatten of signal with signal as value
      a.post(b)
      testCase.verifyEqual(flat.Node.Value, val, 'Unexpected node value')
      b.post(rand)
      testCase.verifyEqual(flat.Node.Value, b.Node.Value, ...
        'failed to retrieve source value')

      % Test new director value with current value
      c.post(rand), a.post(c)
      testCase.verifyEqual(flat.Node.Value, c.Node.Value)
    end
    %
    % function test_nop(testCase)
    %   % Test the NOP transfer function
    %   [a, b] = deal(testCase.A, testCase.B);
    %   netId = testCase.net.Id;
    %   warnId = 'signals:transfer:nopCalled';
    %   executable = @() sig.transfer.nop(netId, a.Node.Id, b.Node.Id, []);
    %   [val, valset] = testCase.verifyWarning(executable, warnId);
    %   testCase.verifyEmpty(val, 'Unexpected value')
    %   testCase.verifyFalse(valset, 'Unexpected value set')
    % end
    %
    % function test_identity(testCase)
    %   % Test the identity transfer function
    %   a = testCase.A;
    %   b = a.identity;
    %
    %   a.post(rand)
    %   testCase.verifyEqual(a.Node.Value, b.Node.Value, ...
    %     'Failed to assign value')
    %
    %   % Test output when no working value
    %   netId = testCase.net.Id;
    %   [val, valset] = sig.transfer.identity(netId, a.Node.Id, b.Node.Id, []);
    %   testCase.verifyEmpty(val, 'Unexpected value')
    %   testCase.verifyFalse(valset, 'Unexpected value set')
    % end
    %
    %
    % function test_setEpochTrigger(testCase)
    %   % Test for setEpochTrigger method
    %   [t, dt, x] = deal(testCase.A, testCase.B, testCase.C);
    %   t.Name = 'duration'; dt.Name = 't'; x.Name = 'x';
    %   tr = setEpochTrigger(t, dt, x);
    %
    %   % Verify name
    %   str = sprintf('%1$s\\w/%1$s\\w < \\w s.t. %1$s\\w = \\w', char(916));
    %   testCase.verifyMatches(tr.Name, str, 'Unexpected Name')
    %
    %   % Verify initialized to false
    %   testCase.verifyFalse(tr.Node.Value, 'Expected ''valset'' to be false')
    %
    %   % Test trigger release
    %   dur = 5;
    %   t.post(dur)
    %   x.post(.1), x.post(.2)
    %   dt.post(0), dt.post(dur + 1)
    %   testCase.verifyTrue(tr.Node.Value, 'Failed to release trigger')
    %
    %   % Test period reset
    %   affectedIdxs = submit(testCase.net.Id, t.Node.Id, dur);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   testCase.verifyFalse(ismember(tr.Node.Id, changed), ...
    %     'Unexpected update to node''s value')
    %
    %   % Test subthreshold time change
    %   newt = dt.Node.Value + dur/2;
    %   affectedIdxs = submit(testCase.net.Id, dt.Node.Id, newt);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   testCase.verifyFalse(ismember(tr.Node.Id, changed), ...
    %     'Unexpected update to node''s value')
    %
    %   % Test position reset
    %   state = tr.Node.Inputs(2).Inputs(1).Inputs(1).Inputs(1);
    %   newx = x.Node.Value^2;
    %   x.post(newx);
    %   testCase.verifyEqual(state.CurrValue.remaining, dur, ...
    %     'Failed to reset period')
    % end
    %
    % function test_size(testCase)
    %   % Test for the size method
    %   a = testCase.A;
    %   n = randi(10);
    %
    %   % 1 input, 1 output
    %   sz = size(a);
    %   testCase.assertTrue(isa(sz, 'sig.Signal'), ...
    %     ['Unexpected output: expected sig.Signal but returned ', class(sz)])
    %   a.post(1:n);
    %   testCase.verifyEqual(sz.Node.Value, [1 n], ...
    %     'Unexpected value for 1 input, 1 output map of size')
    %   % Verify Name property
    %   testCase.verifyMatches(sz.Name, 'size\(\w+\)', 'Unexpected Name')
    %
    %   % 1 input, 2 outputs
    %   [sz_m, sz_n] = size(a);
    %   a.post(1:n)
    %   actual = [sz_m.Node.Value, sz_n.Node.Value];
    %   testCase.verifyEqual(actual, [1 n], ...
    %     'Unexpected value for 1 input, 1 output map of size')
    %   % Verify Name property
    %   expected = 'size\(\w+\) over dim \d+';
    %   testCase.verifyMatches(sz_m.Name, expected, 'Unexpected Name')
    %   testCase.verifyMatches(sz_n.Name, expected, 'Unexpected Name')
    %
    %   % 2 input, 1 output
    %   [sz] = size(a, 2);
    %   a.post(1:n)
    %   testCase.verifyEqual(sz.Node.Value, n, ...
    %     'Unexpected value for map of size along specified dimention')
    %
    %   % 2 inputs, 2 outputs
    %   [~, sz] = size(a, 2);  %#ok<*ASGLU>
    %   % Note in 2019b error id changed
    %   id = iff(verLessThan('matlab', '9.7'), ...
    %       'MATLAB:maxlhs', 'MATLAB:size:NumOutNotEqualNumDims');
    %   testCase.verifyError(@()a.post(1:n), id, 'Unexpected error identifier')
    % end
    %
    % function test_output(testCase)
    %   % Test for the output method
    %   a = testCase.A;
    %   h = output(a);
    %
    %   testCase.verifyTrue(isa(h, 'TidyHandle'), ...
    %     sprintf('Expected TidyHandle but %s was returned instead', class(h)))
    %
    %   % Test output
    %   val = randi(10000);
    %   out = strtrim(evalc('a.post(val)'));
    %   testCase.verifyEqual(out, num2str(val), 'Unexpected output')
    %
    %   % Test cleanup
    %   clear('h')
    %   out = strtrim(evalc('a.post(val)'));
    %   testCase.verifyEmpty(out, 'Output persists after removing listener')
    % end
    %
    % function test_colon(testCase)
    %   % Test for the colon method
    %   [a, b, c] = deal(testCase.A, testCase.B, testCase.C);
    %   i = 3; j = 14; k = 0.5;
    %
    %   % Test two inputs
    %   s = a:b;
    %   a.post(i), b.post(j)
    %   testCase.verifyEqual(s.Node.Value, i:j, 'Failed on two input')
    %   testCase.verifyMatches(s.Name, '\w+ : \w+', 'Unexpected Name')
    %
    %   % Test three inputs
    %   s = a:c:b;
    %   c.post(k)
    %   testCase.verifyEqual(s.Node.Value, i:k:j, 'Failed on three input')
    %   testCase.verifyMatches(s.Name, '\w+ : \w+ : \w+', 'Unexpected Name')
    % end
    %
    % function test_min(testCase)
    %   % Test for the min method
    %   [a, b] = deal(testCase.A, testCase.B);
    %
    %   [M,I] = min(a);
    %   a.post(magic(3))
    %   testCase.verifyEqual(M.Node.Value, [3,1,2], ...
    %     'Failed to return minimum values')
    %   testCase.verifyEqual(I.Node.Value, [2,1,3], ...
    %     'Failed to return indicies')
    %   testCase.verifyMatches(M.Name, 'min\(\w+\)', 'Unexpected Name')
    %
    %   [M,I] = min(a,[],b);
    %   expected = 'min\(\w+\) over dim \w+';
    %   testCase.verifyMatches(M.Name, expected, 'Unexpected Name')
    %   post(b,2)
    %   testCase.verifyEqual(M.Node.Value, [1;3;2], ...
    %     'Failed to return minimum values')
    %   testCase.verifyEqual(I.Node.Value, [2;1;3], ...
    %     'Failed to return indicies')
    %
    %   clear('I')
    %   M = min(a,b);
    %   testCase.verifyMatches(M.Name, 'min\(\w+,\w+\)', 'Unexpected Name')
    %   post(a,magic(2)), post(b,2)
    %   testCase.verifyEqual(M.Node.Value, [1,2;2,2], ...
    %     'Failed to return minimum values')
    % end
    %
    % function test_max(testCase)
    %   % Test for the max method
    %   [a, b] = deal(testCase.A, testCase.B);
    %
    %   [M,I] = max(a);
    %   a.post(magic(3))
    %   testCase.verifyEqual(M.Node.Value, [8,9,7], ...
    %     'Failed to return maximum values')
    %   testCase.verifyEqual(I.Node.Value, [1,3,2], ...
    %     'Failed to return indicies')
    %   testCase.verifyMatches(M.Name, 'max\(\w+\)', 'Unexpected Name')
    %
    %   [M,I] = max(a,[],b);
    %   expected = 'max\(\w+\) over dim \w+';
    %   testCase.verifyMatches(M.Name, expected, 'Unexpected Name')
    %   post(b,2)
    %   testCase.verifyEqual(M.Node.Value, [8;7;9], ...
    %     'Failed to return maximum values')
    %   testCase.verifyEqual(I.Node.Value, [1;3;2], ...
    %     'Failed to return indicies')
    %
    %   clear('I')
    %   M = max(a,b);
    %   testCase.verifyMatches(M.Name, 'max\(\w+,\w+\)', 'Unexpected Name')
    %   post(a,magic(2)), post(b,2)
    %   testCase.verifyEqual(M.Node.Value, [2,3;4,2], ...
    %     'Failed to return maximum values')
    % end
    %
    % function test_exp(testCase)
    %   % Test for the exp method
    %   a = testCase.A;
    %   b = exp(a);
    %   e = exp(1);
    %
    %   testCase.verifyMatches(b.Name, 'exp\(\w+\)', 'Unexpected Name')
    %   a.post(1)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_erf(testCase)
    %   % Test for the exp method
    %   a = testCase.A;
    %   b = erf(a); % our method to test
    %   x = [-0.5 0 1 0.72]; % values to test
    %   e = erf(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'erf\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_sqrt(testCase)
    %   % Test for the sqrt method
    %   a = testCase.A;
    %   b = sqrt(a); % our method to test
    %   x = -2:2; % values to test
    %   e = sqrt(x); % expected output
    %
    %   rootSym = char(hex2dec('221A'));
    %   testCase.verifyMatches(b.Name, [rootSym,'\(\w+\)'], 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_str2num(testCase)
    %   % Test for the str2num method
    %   a = testCase.A;
    %   b = a.str2num; % our method to test
    %   str = '234.54'; % string to test
    %
    %   testCase.verifyMatches(b.Name, 'str2num\(\w+\)', 'Unexpected Name')
    %   a.post(str)
    %   testCase.verifyEqual(b.Node.Value, str2double(str))
    % end
    %
    % function test_num2str(testCase)
    %   % Test for the num2str method
    %   a = testCase.A;
    %   b = num2str(a); % our method to test
    %   b_pres = num2str(a, 3);
    %   n = rand; % number to convert
    %
    %   testCase.verifyMatches(b.Name, 'num2str\(\w+\)', 'Unexpected Name')
    %   a.post(n)
    %   testCase.verifyEqual(b.Node.Value, num2str(n))
    %   testCase.verifyEqual(b_pres.Node.Value, num2str(n, 3))
    % end
    %
    % function test_fliplr(testCase)
    %   % Test for the fliplr method
    %   a = testCase.A;
    %   b = fliplr(a); % our method to test
    %   x = magic(6); % values to test
    %   e = fliplr(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'fliplr\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_flipud(testCase)
    %   % Test for the flipud method
    %   a = testCase.A;
    %   b = flipud(a); % our method to test
    %   x = magic(6); % values to test
    %   e = flipud(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'flipud\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_rot90(testCase)
    %   % Test for the rot90 method
    %   a = testCase.A;
    %   b = rot90(a); % our method to test
    %   x = magic(6); % values to test
    %   e = rot90(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'rot90\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    %   % test second input
    %   b = rot90(a,4);
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, x)
    % end
    %
    % function test_any(testCase)
    %   % Test for the any method
    %   a = testCase.A;
    %   b = any(a); % our method to test
    %   x = eye(6); % values to test
    %   e = any(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'any\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    %   % test second input
    %   b = any(a,'all');
    %   a.post(x)
    %   testCase.verifyTrue(b.Node.Value)
    % end
    %
    % function test_all(testCase)
    %   % Test for the all method
    %   a = testCase.A;
    %   b = all(a); % our method to test
    %   x = eye(6); % values to test
    %   e = all(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'all\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    %   % test second input
    %   b = all(a,'all');
    %   a.post(x)
    %   testCase.verifyFalse(b.Node.Value)
    % end
    %
    % function test_floor(testCase)
    %   % Test for the floor method
    %   a = testCase.A;
    %   b = floor(a); % our method to test
    %   x = 12 + rand; % value to test
    %   e = floor(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'floor\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_abs(testCase)
    %   % Test for the floor method
    %   a = testCase.A;
    %   b = abs(a); % our method to test
    %   x = -4:4; % values to test
    %   e = abs(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, '|\w+|', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_sign(testCase)
    %   % Test for the sign method
    %   a = testCase.A;
    %   b = sign(a); % our method to test
    %   x = -4:4; % values to test
    %   e = sign(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'sgn\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_sin(testCase)
    %   % Test for the sin method
    %   a = testCase.A;
    %   b = sin(a); % our method to test
    %   x = -pi:0.01:pi; % values to test
    %   e = sin(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'sin\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end
    %
    % function test_cos(testCase)
    %   % Test for the cos method
    %   a = testCase.A;
    %   b = cos(a); % our method to test
    %   x = -pi:0.01:pi; % values to test
    %   e = cos(x); % expected output
    %
    %   testCase.verifyMatches(b.Name, 'cos\(\w+\)', 'Unexpected Name')
    %   a.post(x)
    %   testCase.verifyEqual(b.Node.Value, e)
    % end

    function test_keepWhen(testCase)
      % Tests for keepWhen method
      [a, b] = deal(testCase.A, testCase.B);
      s = a.keepWhen(b);
      testCase.verifyMatches(s.Name, '\w+\.keepWhen\(\w+\)', 'Unexpected Name')

      % Gate not yet set — a fires but s stays empty
      a.post(rand)
      testCase.verifyEmpty(s.Node.Value, 'Expected s empty when gate unset')

      % Gate truthy — a fires, s passes through
      b.post(true)
      v = rand;
      a.post(v)
      testCase.verifyEqual(s.Node.Value, v, 'Expected s to pass through when gate truthy')

      % Gate fires alone — s must not appear in the affected set at all
      affected = testCase.net.transact(b, false);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Expected s not affected when only gate fires')
      testCase.net.apply(affected);

      % Gate falsy — a fires, s blocked
      a.post(rand)
      testCase.verifyEqual(s.Node.Value, v, 'Expected s blocked when gate falsy')

      % Test when a not set
      aa = testCase.net.origin('a');
      bb = testCase.net.origin('b');
      testCase.addTeardown(@delete, aa)
      testCase.addTeardown(@delete, bb)

      s = aa.keepWhen(bb);

      % Post a truthy value to b
      affected = testCase.net.transact(bb, true);
      % Check only b's node affected
      testCase.verifyTrue(isequal(affected, bb.Node.Id), ...
        'Unexpected nodes affected when predicate signal true')
      testCase.net.apply(affected);

      % Post a value to signal a
      v = rand;
      affected = testCase.net.transact(aa, v);
      % Check a and s nodes changed
      testCase.verifyTrue(isequal(affected, [aa.Node.Id s.Node.Id]), ...
        'Unexpected network behaviour upon posting value to signal a')
      testCase.net.apply(affected);
      testCase.verifyTrue(isequal(v, aa.Node.Value, s.Node.Value), ...
        'Unexpected values of signals a and s')
    end

    function test_at(testCase)
      % Test for the at method
      [a, b] = deal(testCase.A, testCase.B);
      s = a.at(b);
      testCase.verifyMatches(s.Name, '\w.at(\w+\)', 'Unexpected Name')

      testCase.at_then_test(s)
    end

    function test_then(testCase)
      % Test for the then method
      [a, b] = deal(testCase.A, testCase.B);
      s = b.then(a);
      testCase.verifyMatches(s.Name, '\w.then(\w+\)', 'Unexpected Name')

      testCase.at_then_test(s)
    end

    function test_to(testCase)
      % Test for the to method (SR-latch: true between arm and release events)
      [a, b] = deal(testCase.A, testCase.B);
      p = a.to(b);
      testCase.verifyMatches(p.Name, '\w+\.to\(\w+\)', 'Unexpected Name')

      % Starts with no value before either input has fired
      testCase.verifyEmpty(p.Node.Value, 'Expected p empty before any event')

      % Release fires before arm — p should not be affected
      affected = testCase.net.transact(b, true);
      testCase.verifyFalse(ismember(p.Node.Id, affected), ...
        'Expected p not affected when release fires before arm')
      testCase.net.apply(affected);
      testCase.verifyEmpty(p.Node.Value, 'Expected p still empty after premature release')

      % Arm fires truthy — p latches true
      a.post(true);
      testCase.verifyTrue(p.Node.Value, 'Expected p true after arm fires truthy')

      % Arm fires again while already armed — p should not re-fire
      affected = testCase.net.transact(a, true);
      testCase.verifyFalse(ismember(p.Node.Id, affected), ...
        'Expected p not affected when arm fires while already armed')
      testCase.net.apply(affected);

      % Arm fires falsy while armed — p should not change
      affected = testCase.net.transact(a, false);
      testCase.verifyFalse(ismember(p.Node.Id, affected), ...
        'Expected p not affected when arm fires falsy')
      testCase.net.apply(affected);

      % Release fires truthy — p latches false
      b.post(true);
      testCase.verifyFalse(p.Node.Value, 'Expected p false after release fires truthy')

      % Release fires again while released — p should not re-fire
      affected = testCase.net.transact(b, true);
      testCase.verifyFalse(ismember(p.Node.Id, affected), ...
        'Expected p not affected when release fires while already released')
      testCase.net.apply(affected);

      % Arm fires truthy again — p re-arms
      a.post(true);
      testCase.verifyTrue(p.Node.Value, 'Expected p true after re-arming')
    end

    function test_setTrigger(testCase)
      % Test for the setTrigger method (one-shot per arm/release cycle)
      [a, b] = deal(testCase.A, testCase.B);
      tr = a.setTrigger(b);
      testCase.verifyMatches(tr.Name, '\w+\.setTrigger\(\w+\)', 'Unexpected Name')

      % Starts with no value before either input has fired
      testCase.verifyEmpty(tr.Node.Value, 'Expected tr empty before any event')

      % Arm fires — tr should NOT fire (only arm, no release yet)
      affected = testCase.net.transact(a, true);
      testCase.verifyFalse(ismember(tr.Node.Id, affected), ...
        'Expected tr not affected when only arm fires')
      testCase.net.apply(affected);
      testCase.verifyEmpty(tr.Node.Value, 'Expected tr still empty after arm only')

      % Release fires truthy — tr fires true
      b.post(true);
      testCase.verifyTrue(tr.Node.Value, 'Expected tr true after release fires truthy')

      % Release fires again without re-arming — tr should NOT fire
      affected = testCase.net.transact(b, true);
      testCase.verifyFalse(ismember(tr.Node.Id, affected), ...
        'Expected tr not affected on second release without re-arm')
      testCase.net.apply(affected);

      % Re-arm then release — tr fires again
      a.post(true);
      testCase.verifyTrue(tr.Node.Value, ...
        'Expected tr still true after re-arm (no change yet)')
      b.post(true);
      testCase.verifyTrue(tr.Node.Value, 'Expected tr true after second arm/release cycle')

      % Release fires falsy — tr should NOT fire even when armed
      a.post(true);  % re-arm
      affected = testCase.net.transact(b, false);
      testCase.verifyFalse(ismember(tr.Node.Id, affected), ...
        'Expected tr not affected when release fires falsy')
      testCase.net.apply(affected);
    end

    function test_indexOfFirst(testCase)
      % Test for the indexOfFirst method
      [a, b] = deal(testCase.A, testCase.B);
      f = indexOfFirst(a, b);
      testCase.verifyMatches(f.Name, 'indexOfFirst\(', 'Unexpected Name')

      % Starts empty before any pred fires
      testCase.verifyEmpty(f.Node.Value, 'Expected f empty before any pred fires')

      % Both preds fire false — no output (neither truthy)
      a.post(false); b.post(false);
      testCase.verifyEmpty(f.Node.Value, 'Expected no output when all preds falsy')

      % Second pred fires truthy — output = 1 (b is inputs[1])
      b.post(true);
      testCase.verifyEqual(f.Node.Value, 1.0, 'Expected index 1 when only b truthy')

      % First pred fires truthy — output = 0 (a wins, b still truthy)
      a.post(true);
      testCase.verifyEqual(f.Node.Value, 0.0, 'Expected index 0 when a truthy (first wins)')

      % First pred fires false — output = 1 (b still truthy)
      a.post(false);
      testCase.verifyEqual(f.Node.Value, 1.0, 'Expected index 1 after a goes false')

      % Second pred fires false — no output (none truthy), value unchanged
      affected = testCase.net.transact(b, false);
      testCase.verifyFalse(ismember(f.Node.Id, affected), ...
        'Expected no output from indexOfFirst when no pred truthy')
      testCase.net.apply(affected);
    end

    function test_selectFrom(testCase)
      % Test for the selectFrom method
      [a, b, c] = deal(testCase.A, testCase.B, testCase.C);
      s = a.selectFrom(b, c);  % a = 0-based index; b = option 0, c = option 1
      testCase.verifyMatches(s.Name, '\.selectFrom\(', 'Unexpected Name')

      % Starts empty before index fires
      testCase.verifyEmpty(s.Node.Value, 'Expected s empty before index fires')

      % Post values to options before index fires — s should not update
      vb = rand; b.post(vb);
      testCase.verifyEmpty(s.Node.Value, 'Expected s empty when only option fires before index')

      % Index fires 0 — s takes b's latest value
      a.post(0);
      testCase.verifyEqual(s.Node.Value, vb, 'Expected s = b when idx = 0')

      % Selected option (b) updates — s fires with new value
      vb2 = rand; b.post(vb2);
      testCase.verifyEqual(s.Node.Value, vb2, 'Expected s to update when selected option fires')

      % Non-selected option (c) updates — s should NOT fire
      vc = rand;
      affected = testCase.net.transact(c, vc);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Expected s not affected when non-selected option fires')
      testCase.net.apply(affected);

      % Switch index to 1 — s takes c's latest value
      a.post(1);
      testCase.verifyEqual(s.Node.Value, vc, 'Expected s = c when idx = 1')

      % Now b (no longer selected) updates — s should NOT fire
      affected = testCase.net.transact(b, rand);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Expected s not affected when previously-selected option fires after switch')
      testCase.net.apply(affected);
    end

    function test_cond(testCase)
      % Test for the cond method
      [a, b] = deal(testCase.A, testCase.B);
      c = cond(a, 10, b, 20);  % if a then 10, if b then 20
      testCase.verifyMatches(c.Name, 'cond\(', 'Unexpected Name')

      % Starts empty before any pred fires
      testCase.verifyEmpty(c.Node.Value, 'Expected cond empty before any pred fires')

      % Second pred fires truthy — c = 20
      b.post(true);
      testCase.verifyEqual(c.Node.Value, 20.0, 'Expected val2 when only pred2 truthy')

      % First pred fires truthy — c = 10 (first pred wins over second)
      a.post(true);
      testCase.verifyEqual(c.Node.Value, 10.0, 'Expected val1 when pred1 truthy (first wins)')

      % First pred fires false — c = 20 (second pred still truthy)
      a.post(false);
      testCase.verifyEqual(c.Node.Value, 20.0, 'Expected val2 when only pred2 truthy')

      % Both preds fire false — no new output, c retains its value
      b.post(false);
      affected = testCase.net.transact(a, false);
      testCase.verifyFalse(ismember(c.Node.Id, affected), ...
        'Expected cond not affected when no pred truthy')
      testCase.net.apply(affected);
      testCase.verifyEqual(c.Node.Value, 20.0, 'Expected c unchanged when no pred truthy')
    end

    function test_iff(testCase)
      % Test for the iff method
      [a, b] = deal(testCase.A, testCase.B);

      % 3-arg form: iff(pred, trueVal, falseVal)
      r = iff(a, 1, 0);
      testCase.verifyMatches(r.Name, 'cond\(', 'Unexpected Name')

      % pred fires truthy — r = 1
      a.post(true);
      testCase.verifyEqual(r.Node.Value, 1.0, 'Expected 1 when pred truthy')

      % pred fires falsy — r = 0 (constant-true fallback pred selects val2)
      a.post(false);
      testCase.verifyEqual(r.Node.Value, 0.0, 'Expected 0 when pred falsy')

      % pred fires truthy again — back to 1
      a.post(true);
      testCase.verifyEqual(r.Node.Value, 1.0, 'Expected 1 when pred truthy again')

      % 2-arg form: iff(pred, trueVal) — no output when pred falsy
      r2 = iff(b, 42);
      b.post(true);
      testCase.verifyEqual(r2.Node.Value, 42.0, 'Expected 42 when pred truthy')

      affected = testCase.net.transact(b, false);
      testCase.verifyFalse(ismember(r2.Node.Id, affected), ...
        'Expected no output from 2-arg iff when pred falsy')
      testCase.net.apply(affected);
      testCase.verifyEqual(r2.Node.Value, 42.0, 'Expected r2 unchanged when pred falsy')
    end

    function test_subsref(testCase)
        % A test for indexing into a signal
        [i, seq] = deal(testCase.A, testCase.B);
        indexed = seq(i);
        testCase.verifyInstanceOf(indexed, 'sig.Signal')
        testCase.verifyTrue(isempty(indexed.Node.Value))
        testCase.verifyEqual(indexed.Name, "b(a)")
        seq.Name = 'sequence';
        testCase.verifyEqual(indexed.Name, "sequence(a)")
        seq.post(1:50)
        testCase.verifyTrue(isempty(indexed.Node.Value))
        i.post(5)
        testCase.verifyEqual(indexed.Node.Value, 5)
        try  % TODO test that standard error raised (Index exceeds the number of array elements (50).)
            i.post(51)
            failToRaise = true;
        catch
            failToRaise = false;
        end
        testCase.verifyFalse(failToRaise)
        seq.post(1:100)
        testCase.verifyEqual(indexed.Node.Value, 51)
        i.post(1)  % avoid error by posting low index

        % Test that it can handle ranges and end
        range = seq(5:10);
        testCase.verifyEqual(range.Name, "sequence(5   6   7   8   9   10)")
        seq.post(1:20)
        testCase.verifyEqual(range.Node.Value, 5:10)
        e = seq(end);
        seq.post(1:50)
        testCase.verifyEqual(e.Node.Value, 50)
        testCase.verifyError(@() seq(end-5:end), 'sig:signal:indexEndRangeError')

        % Finally test behaviour when seq uninitialized
        seq2 = testCase.C;
        indexed = seq2(i);
        testCase.verifyTrue(isempty(indexed.Node.Value))
        seq2.post(1:100)
        testCase.verifyEqual(indexed.Node.Value, 1)
    end
  end

  methods (Access = private)
    function at_then_test(testCase, s)
      % AT_THEN_TEST Common tests for `at` and `then` methods
      %   This function is called by both the test_at and test_then methods

      [parent, child] = distribute(s.Node.Inputs);

      % Post a value to parent (a) — only a should be affected; s is
      % gate-triggered so it does not fire when only its value source updates
      v = rand;
      affected = testCase.net.transact(parent, v);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Unexpected network behaviour upon posting value to signal a')
      testCase.net.apply(affected);

      % Post a truthy value to child (b) — b and s should both be affected
      affected = testCase.net.transact(child, true);
      testCase.verifyTrue(ismember(child.Id, affected), ...
        'Expected child node in affected set')
      testCase.verifyTrue(ismember(s.Node.Id, affected), ...
        'Unexpected network behaviour upon posting value to signal b')
      testCase.net.apply(affected);
      testCase.verifyTrue(isequal(v, parent.Value, s.Node.Value), ...
        'Unexpected values of signals a and s')

      % Post a new value to parent (a) — only a should be affected: unlike
      % keepWhen, s will not fire as b has not changed since last update
      v = rand;
      affected = testCase.net.transact(parent, v);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Unexpected network behaviour upon posting value to signal a')
      testCase.net.apply(affected);
      testCase.verifyTrue(v == parent.Value && s.Node.Value ~= v, ...
        'Unexpected values of signals a and s')

      % Post a non-truthy value to child (b) — s should not be affected
      affected = testCase.net.transact(child, false);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Unexpected nodes affected when predicate signal false')
      testCase.net.apply(affected);

      % Post a value to parent (a) — s should still not fire (gate is false)
      v = rand;
      affected = testCase.net.transact(parent, v);
      testCase.verifyFalse(ismember(s.Node.Id, affected), ...
        'Unexpected network behaviour upon posting value to signal a')
      testCase.net.apply(affected);
      testCase.verifyTrue(v == parent.Value && s.Node.Value ~= v, ...
        'Unexpected values of signals a and s')
    end

  end
end