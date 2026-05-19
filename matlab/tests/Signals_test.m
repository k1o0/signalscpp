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
    % function test_bufferUpTo(testCase)
    %   % Test for bufferUpTo method
    %   a = testCase.A;
    %   b = a.bufferUpTo(3);
    %
    %   a.post(randi(1e4))
    %   testCase.verifyEqual(b.Node.Value, a.Node.Value, ...
    %     'Unexpected output when bufferUpTo')
    %   testCase.verifyMatches(b.Name, '\w+\.bufferUpTo\(\d+)', 'Unexpected Name')
    %
    %   % Test filling buffer
    %   vals = rand(1,4);
    %   arrayfun(@(v) a.post(v), vals)
    %   testCase.verifyEqual(b.Node.Value, vals(end-2:end), ...
    %     'Fails to buffer up to sample number')
    %
    %   % Test transfer function directly; no new changes in network
    %   % ids = pick([b.Node.Inputs], 'Id') % Same as below, requires Rigbox
    %   inIds = arrayfun(@(n) n.Id, b.Node.Inputs);
    %   args = {testCase.net.Id, inIds, b.Node.Id};
    %   [~, valset] = sig.transfer.buffer(args{:});
    %   testCase.verifyFalse(valset, 'Expected ''valset'' to be false')
    %
    %   % Update one of the input nodes
    %   expected = sort(cellfun(@(n) n.Node.Id, {a,b}));
    %   actual = submit(testCase.net.Id, a.Node.Id, rand);
    %   testCase.verifyEqual(expected(:), actual, ...
    %     'Unexpected affected node indicies returned')
    %   [val, valset] = sig.transfer.buffer(args{:});
    %   testCase.verifyTrue(valset, 'Expected ''valset'' to be true')
    %   testCase.verifyEqual(val(end), a.Node.WorkingValue, 'Failed to re-evaluate function')
    %
    %   % Test N samples as signal
    %   b = testCase.B;
    %   buff = a.bufferUpTo(b);
    %   testCase.verifyMatches(buff.Name, '\w+\.bufferUpTo\(\w+)', 'Unexpected Name')
    %
    %   % No updates until n samples defined
    %   a.post(rand)
    %   inIds = arrayfun(@(n) n.Id, buff.Node.Inputs);
    %   args = {testCase.net.Id, inIds, buff.Node.Id};
    %   [~, valset] = sig.transfer.buffer(args{:});
    %   testCase.verifyFalse(valset, 'Expected ''valset'' to be false')
    %
    %   % Initialize N samples
    %   n = 3;
    %   b.post(n), arrayfun(@(v) a.post(v), rand(1,n))
    %   expected = ...
    %     numel(buff.Node.Value) == n && ...
    %     buff.Node.Value(end) == a.Node.Value;
    %   testCase.verifyTrue(expected, ...
    %     'Unexpected output when nSamples is signal')
    %
    %   % Test restricting n samples
    %   b.post(b.Node.Value-1)
    %   [~, valset] = sig.transfer.buffer(args{:});
    %   testCase.verifyFalse(valset, 'Expected ''valset'' to be false')
    %   a.post(rand)
    %   expected = ...
    %     numel(buff.Node.Value) == n-1 && ...
    %     buff.Node.Value(end) == a.Node.Value;
    %   testCase.verifyTrue(expected, ...
    %     'Unexpected output when nSamples is signal')
    % end
    %
    % function test_buffer(testCase)
    %   % Test for buffer method.  For thorough testing use test_bufferUpTo
    %   a = testCase.A;
    %   n = 3;
    %   b = a.buffer(n);
    %
    %   % Test unfilled buffer
    %   a.post(rand)
    %   testCase.verifyEmpty(b.Node.Value, ...
    %     'Expected buffer to be uninitialized while nUpdates < n')
    %   testCase.verifyMatches(b.Name, '\w+\.buffer\(\d+)', 'Unexpected Name')
    %
    %   % Test filling buffer
    %   vals = rand(1,n);
    %   arrayfun(@(v) a.post(v), vals)
    %   testCase.verifyEqual(b.Node.Value, vals(end-2:end), ...
    %     'Fails to buffer up to sample number')
    % end

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
    %
    % function test_keepWhen(testCase)
    %   % Test for the keepWhen method
    %   [a, b] = deal(testCase.A, testCase.B);
    %   s = a.keepWhen(b);
    %   testCase.verifyMatches(s.Name, '\w.keepWhen(\w+\)', 'Unexpected Name')
    %
    %   % Post a truthy value to b
    %   affectedIdxs = submit(testCase.net.Id, b.Node.Id, true);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   % Check only b's node affected
    %   testCase.verifyTrue(isequal(affectedIdxs, changed, b.Node.Id), ...
    %     'Unexpected nodes affected when predicate signal true')
    %
    %   % Post a value to signal a
    %   v = rand;
    %   affectedIdxs = submit(testCase.net.Id, a.Node.Id, v);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   % Check a and s nodes changed
    %   testCase.verifyTrue(isequal(affectedIdxs, changed, [a.Node.Id;s.Node.Id]), ...
    %     'Unexpected network behaviour upon posting value to signal a')
    %   testCase.verifyTrue(isequal(v, a.Node.Value, s.Node.Value), ...
    %     'Unexpected values of signals a and s')
    %
    %   % Post a non-truthy value to b
    %   affectedIdxs = submit(testCase.net.Id, b.Node.Id, false);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   % Check only b's node affected
    %   testCase.verifyTrue(isequal(affectedIdxs, changed, b.Node.Id), ...
    %     'Unexpected nodes affected when predicate signal false')
    %
    %   % Post a value to signal a
    %   v = rand;
    %   affectedIdxs = submit(testCase.net.Id, a.Node.Id, v);
    %   changed = applyNodes(testCase.net.Id, affectedIdxs);
    %   % Check only a's node affected
    %   testCase.verifyTrue(isequal(affectedIdxs, changed, a.Node.Id), ...
    %     'Unexpected network behaviour upon posting value to signal a')
    %   testCase.verifyTrue(v == a.Node.Value && s.Node.Value ~= v, ...
    %     'Unexpected values of signals a and s')
    % end
    %
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