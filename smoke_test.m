%% smoke_test.m — quick sanity check for the sig.Net MEX bindings
%
% Run with:
%   cd 'c:\Users\Work\source\repos\signalscpp'
%   smoke_test

% ── Path setup ────────────────────────────────────────────────────────────────
% The install folder contains +libmexclass/+proxy/ (gateway.mexw64 + Proxy.m)
addpath('c:\Users\Work\source\repos\signalscpp\install_mex\Signals\mex\matlab');
% The source tree contains +sig/ (Net.m)
addpath('c:\Users\Work\source\repos\signalscpp\Signals\mex\matlab');

% ── Test 1: construction and isValid ─────────────────────────────────────────
net = sig.Net(1000);
assert(net.isValid(), 'isValid() should return true after construction');
fprintf('[PASS] Construction and isValid\n');

% ── Test 2: addNode (source / nop) ───────────────────────────────────────────
% op 51 = Operation::nop (source node)
srcId = net.addNode([], 51, false);
assert(srcId >= 0, 'addNode should return a valid id >= 0');
fprintf('[PASS] addNode (nop source, id=%d)\n', srcId);

% ── Test 3: transact + apply + getCurrentValue ───────────────────────────────
affected = net.transact(srcId, 42.0);
assert(~isempty(affected), 'transact should return at least one affected id');
net.apply(affected);
v = net.getCurrentValue(srcId);
assert(isequal(v, 42.0), sprintf('Expected 42.0, got %s', mat2str(v)));
fprintf('[PASS] transact+apply+getCurrentValue (value=%.6g)\n', v);

% ── Test 4: second transact overwrites value ──────────────────────────────────
affected = net.transact(srcId, 99.5);
net.apply(affected);
v2 = net.getCurrentValue(srcId);
assert(isequal(v2, 99.5), sprintf('Expected 99.5, got %s', mat2str(v2)));
fprintf('[PASS] Second transact (value=%.6g)\n', v2);

% ── Test 5: nActiveNodes (at least 1) ────────────────────────────────────────
n = net.nActiveNodes();
assert(n >= 1, 'Should have at least 1 active node');
fprintf('[PASS] nActiveNodes = %d\n', n);

% ── Test 6: identity (downstream) node ───────────────────────────────────────
% op 50 = Operation::identity
downId = net.addNode(srcId, 50, false);
assert(downId >= 0, 'downstream addNode should succeed');
affected = net.transact(srcId, 7.0);
net.apply(affected);
v_src  = net.getCurrentValue(srcId);
v_down = net.getCurrentValue(downId);
assert(isequal(v_src, 7.0), 'source should be 7.0');
assert(isequal(v_down, 7.0), 'identity node should propagate 7.0');
fprintf('[PASS] Identity propagation (src=%.6g, down=%.6g)\n', v_src, v_down);

% ── Test 7: deleteNode ───────────────────────────────────────────────────────
net.deleteNode(downId);
n2 = net.nActiveNodes();
assert(n2 < n + 1, 'nActiveNodes should decrease after deleteNode');
fprintf('[PASS] deleteNode\n');

% ── Test 8: string value round-trip ──────────────────────────────────────────
strId = net.addNode([], 51, false);
affected = net.transact(strId, "hello");
net.apply(affected);
sv = net.getCurrentValue(strId);
assert(isstring(sv) && sv == "hello", 'String value should round-trip');
fprintf('[PASS] String value round-trip\n');

% ── Test 9: logical value round-trip ─────────────────────────────────────────
boolId = net.addNode([], 51, false);
affected = net.transact(boolId, true);
net.apply(affected);
bv = net.getCurrentValue(boolId);
assert(islogical(bv) && bv == true, 'Logical value should round-trip');
fprintf('[PASS] Logical value round-trip\n');

% ── All done ─────────────────────────────────────────────────────────────────
fprintf('\n=== All smoke tests PASSED ===\n');
