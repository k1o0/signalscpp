%% smoke_test.m — quick sanity check for the sig.Net MEX bindings
%
% Run with:
%   cd 'c:\Users\Work\source\repos\signalscpp'
%   matlab/tests/smoke_test   (or run from matlab/tests/ with no args)

% ── Path setup ────────────────────────────────────────────────────────────────
% matlab/ contains both +sig/ (source) and +libmexclass/ (installed MEX).
addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));
% If running from the repo root instead, uncomment:
% addpath('c:\Users\Work\source\repos\signalscpp\matlab');

% ── Test 1: construction and isValid ─────────────────────────────────────────
net = sig.Net(1000);
assert(net.isValid(), 'isValid() should return true after construction');
fprintf('[PASS] Construction and isValid\n');

% ── Test 2: addNode (source / nop) ───────────────────────────────────────────
srcNode = net.addNode([], sig.OpCode.nop, false);
assert(isa(srcNode, 'sig.Node'),  'addNode should return a sig.Node');
assert(srcNode.Id >= 0, 'node id should be >= 0');
fprintf('[PASS] addNode (nop source, id=%d)\n', srcNode.Id);

% ── Test 3: transact + apply + getCurrentValue ───────────────────────────────
affected = net.transact(srcNode, 42.0);
assert(~isempty(affected), 'transact should return at least one affected id');
net.apply(affected);
v = net.getCurrentValue(srcNode);
assert(isequal(v, 42.0), sprintf('Expected 42.0, got %s', mat2str(v)));
fprintf('[PASS] transact+apply+getCurrentValue (value=%.6g)\n', v);

% ── Test 4: second transact overwrites value ──────────────────────────────────
affected = net.transact(srcNode, 99.5);
net.apply(affected);
v2 = net.getCurrentValue(srcNode);
assert(isequal(v2, 99.5), sprintf('Expected 99.5, got %s', mat2str(v2)));
fprintf('[PASS] Second transact (value=%.6g)\n', v2);

% ── Test 5: nActiveNodes (at least 1) ────────────────────────────────────────
n = net.nActiveNodes();
assert(n >= 1, 'Should have at least 1 active node');
fprintf('[PASS] nActiveNodes = %d\n', n);

% ── Test 6: identity (downstream) node ───────────────────────────────────────
downNode = net.addNode(srcNode, sig.OpCode.identity, false);
assert(downNode.Id >= 0, 'downstream addNode should succeed');
affected = net.transact(srcNode, 7.0);
net.apply(affected);
v_src  = net.getCurrentValue(srcNode);
v_down = net.getCurrentValue(downNode);
assert(isequal(v_src, 7.0), 'source should be 7.0');
assert(isequal(v_down, 7.0), 'identity node should propagate 7.0');
fprintf('[PASS] Identity propagation (src=%.6g, down=%.6g)\n', v_src, v_down);

% ── Test 7: deleteNode ───────────────────────────────────────────────────────
net.deleteNode(downNode);
n2 = net.nActiveNodes();
assert(n2 < n + 1, 'nActiveNodes should decrease after deleteNode');
fprintf('[PASS] deleteNode\n');

% ── Test 8: string value round-trip ──────────────────────────────────────────
strNode = net.addNode([], sig.OpCode.nop, false);
affected = net.transact(strNode, "hello");
net.apply(affected);
sv = net.getCurrentValue(strNode);
assert(isstring(sv) && sv == "hello", 'String value should round-trip');
fprintf('[PASS] String value round-trip\n');

% ── Test 9: logical value round-trip ─────────────────────────────────────────
boolNode = net.addNode([], sig.OpCode.nop, false);
affected = net.transact(boolNode, true);
net.apply(affected);
bv = net.getCurrentValue(boolNode);
assert(islogical(bv) && bv == true, 'Logical value should round-trip');
fprintf('[PASS] Logical value round-trip\n');

% ── All done ─────────────────────────────────────────────────────────────────
fprintf('\n=== All smoke tests PASSED ===\n');
