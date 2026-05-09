% transfer_test.m — MATLAB-level tests for map / filter / scan / nElems / mapn
% Run from the matlab/ directory (or any directory with +sig on the path).
%
% Usage:
%   results = runtests('tests/transfer_test.m')
%
% All tests follow the transact→apply pattern:
%   1. Post a value to the source node with net.transact()
%   2. Commit with net.apply()
%   3. Check the derived node's CurrentValue

function tests = transfer_test
    % Ensure matlab/ (parent of tests/) is on the path so +sig is found.
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    tests = functiontests(localfunctions);
end

% ---------------------------------------------------------------------------
% Fixtures
% ---------------------------------------------------------------------------
function setup(testCase)
    testCase.TestData.net = sig.Net();
end

function teardown(testCase)
    % no explicit teardown needed; GC handles the Net proxy
end

% ---------------------------------------------------------------------------
% Helper: post value → apply → return derived node's CurrentValue
% ---------------------------------------------------------------------------
function v = post(net, src, val, derived)
    affected = net.transact(src, val);
    net.apply(affected);
    v = derived.CurrentValue;
end

% ---------------------------------------------------------------------------
% map tests
% ---------------------------------------------------------------------------
function test_map_doubles_input(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);     % nop source
    out = src.map(@(x) x * 2);

    v = post(net, src, 5, out);
    testCase.verifyEqual(v, 10.0, 'map should double the input');
end

function test_map_string(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    out = src.map(@(x) x + 1);

    v = post(net, src, 3, out);
    testCase.verifyEqual(v, 4.0);
end

function test_map_does_not_fire_without_new_input(testCase)
    % After a second transact on an unrelated node, out should be unchanged.
    net = testCase.TestData.net;
    src  = net.addNode([], 51, false);
    out  = src.map(@(x) x * 3);
    post(net, src, 2, out);  % first tick

    % src2 update should not affect out
    src2 = net.addNode([], 51, false);
    affected = net.transact(src2, 99);
    net.apply(affected);
    testCase.verifyEqual(out.CurrentValue, 6.0, ...
        'map should not fire when its input has no new working value');
end

% ---------------------------------------------------------------------------
% filter tests
% ---------------------------------------------------------------------------
function test_filter_passes_positive(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    out = src.filter(@(x) x > 0);

    v = post(net, src, 7, out);
    testCase.verifyEqual(v, 7.0, 'filter should pass positive values');
end

function test_filter_blocks_negative(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    out = src.filter(@(x) x > 0);

    post(net, src, 5, out);   % seed a current value
    post(net, src, -3, out);  % should be blocked
    testCase.verifyEqual(out.CurrentValue, 5.0, ...
        'filter should block negative values, leaving CurrentValue unchanged');
end

% ---------------------------------------------------------------------------
% scan tests
% ---------------------------------------------------------------------------
function test_scan_running_sum(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    acc = src.scan(@(s, x) s + x, 0);

    post(net, src, 1, acc);
    testCase.verifyEqual(acc.CurrentValue, 1.0);

    post(net, src, 2, acc);
    testCase.verifyEqual(acc.CurrentValue, 3.0);

    post(net, src, 10, acc);
    testCase.verifyEqual(acc.CurrentValue, 13.0, 'scan should track running sum');
end

function test_scan_no_value_before_first_tick(testCase)
    % The seed is the initial accumulator for the fold, not the scan node's
    % initial output.  Before any item fires, the scan node has no value.
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    acc = src.scan(@(s, x) s + x, 100);

    testCase.verifyTrue(isempty(acc.CurrentValue), ...
        'scan node should have no value before any item fires');
end

function test_scan_respects_seed(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    acc = src.scan(@(s, x) s + x, 10);

    post(net, src, 5, acc);
    testCase.verifyEqual(acc.CurrentValue, 15.0, ...
        'scan first tick should use seed as accumulator');
end

% ---------------------------------------------------------------------------
% origin test
% ---------------------------------------------------------------------------
function test_origin_has_constant_value(testCase)
    net = testCase.TestData.net;
    c = net.origin();
    c.post(42);
    testCase.verifyEqual(c.CurrentValue, 42.0, 'origin node should have CurrentValue = 42 after post');
end

% ---------------------------------------------------------------------------
% scan with signal seed (live reset)
% ---------------------------------------------------------------------------
function test_scan_signal_seed_resets_accumulator(testCase)
    net  = testCase.TestData.net;
    src  = net.addNode([], 51, false);
    seed = net.addNode([], 51, false);   % live signal, not a constant
    acc  = src.scan(@(s, x) s + x, seed);

    % Prime the seed (acts as reset / initial accumulator).
    net.apply(net.transact(seed, 0));
    testCase.verifyEqual(acc.CurrentValue, 0.0, 'seed fire should initialise accumulator');

    % Fold a few values.
    net.apply(net.transact(src, 5));
    testCase.verifyEqual(acc.CurrentValue, 5.0);
    net.apply(net.transact(src, 3));
    testCase.verifyEqual(acc.CurrentValue, 8.0);

    % Reset via a new seed value.
    net.apply(net.transact(seed, 100));
    testCase.verifyEqual(acc.CurrentValue, 100.0, ...
        'seed update should reset accumulator');

    % Continue folding from the new seed.
    net.apply(net.transact(src, 1));
    testCase.verifyEqual(acc.CurrentValue, 101.0, ...
        'fold should continue from reset accumulator');
end

function test_scan_does_not_fold_before_seed(testCase)
    % When the seed is a live signal (no constant bootstrap), the scan should
    % not produce output until the seed has fired at least once.
    net  = testCase.TestData.net;
    src  = net.addNode([], 51, false);
    seed = net.addNode([], 51, false);
    acc  = src.scan(@(s, x) s + x, seed);

    net.apply(net.transact(src, 99));   % item fires before seed
    testCase.verifyTrue(isempty(acc.CurrentValue), ...
        'scan should produce no output before the seed has fired');
end
function test_numel_scalar(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    n   = src.nElems();

    v = post(net, src, 42, n);
    testCase.verifyEqual(v, 1.0, 'numel of scalar should be 1');
end

function test_numel_vector(testCase)
    net = testCase.TestData.net;
    src = net.addNode([], 51, false);
    n   = src.nElems();

    v = post(net, src, [1 2 3 4 5], n);
    testCase.verifyEqual(v, 5.0, 'numel of 5-element vector should be 5');
end

% ---------------------------------------------------------------------------
% mapn test
% ---------------------------------------------------------------------------
function test_mapn_two_inputs(testCase)
    net  = testCase.TestData.net;
    srcA = net.addNode([], 51, false);
    srcB = net.addNode([], 51, false);
    out  = srcA.mapn(srcB, @(a, b) a + b);

    % Prime both sources so mapn has a latest value for each.
    net.apply(net.transact(srcA, 3));
    net.apply(net.transact(srcB, 7));

    testCase.verifyEqual(out.CurrentValue, 10.0, ...
        'mapn should sum two inputs');
end

function test_mapn_fires_when_one_input_updates(testCase)
    net  = testCase.TestData.net;
    srcA = net.addNode([], 51, false);
    srcB = net.addNode([], 51, false);
    out  = srcA.mapn(srcB, @(a, b) a * b);

    net.apply(net.transact(srcA, 4));
    net.apply(net.transact(srcB, 5));  % out = 4*5 = 20
    testCase.verifyEqual(out.CurrentValue, 20.0);

    % Update only srcA; out should recompute using latest srcB
    net.apply(net.transact(srcA, 2));  % out = 2*5 = 10
    testCase.verifyEqual(out.CurrentValue, 10.0, ...
        'mapn should recompute using latest value of unchanged input');
end
