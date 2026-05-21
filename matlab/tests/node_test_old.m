%% node_test.m — Tests for sig.Node proxy methods
%
% Run with:
%   cd 'c:\Users\Work\source\repos\signalscpp'
%   matlab/tests/node_test   (or run from matlab/tests/ with no args)

% ── Path setup ────────────────────────────────────────────────────────────────
% matlab/ contains both +sig/ (source) and +libmexclass/ (installed MEX).
addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));
% If running from the repo root instead, uncomment:
% addpath('c:\Users\Work\source\repos\signalscpp\matlab');

net = sig.Net(500);

% ── Test 1: addNode returns a sig.Signal ─────────────────────────────────────
node = net.addNode(sig.Node.empty(1, 0), sig.OpCode.nop, false);
assert(isa(node, 'sig.Node'), 'addNode must return a sig.Node');
fprintf('[PASS] addNode returns sig.Node\n');

% ── Test 2: sig.Node.Id is a non-negative numeric scalar ──────────────
assert(isnumeric(node.Id) && isscalar(node.Id) && node.Id >= 0, ...
    'sig.Id must be a non-negative numeric scalar');
fprintf('[PASS] sig.Id = %d\n', node.Id);

% ── Test 3: Value is [] before any transact ──────────────────────────────────
v = node.Value;
assert(isempty(v), 'Value should be [] before any transact');
fprintf('[PASS] Value is [] before transact\n');

% ── Test 4: Value is [] before any commit ────────────────────────────────────
v = node.Value;
assert(isempty(v), 'Value should be [] when no value has been committed');
fprintf('[PASS] Value is [] with no committed value\n');

% ── Test 5: Value reflects committed value after transact+apply ──────────────
affected = net.transact(node, 3.14);
net.apply(affected);
v = node.Value;
assert(isequal(v, 3.14), sprintf('Expected 3.14, got %s', mat2str(v)));
fprintf('[PASS] Value = %.4g after transact+apply\n', v);

% ── Test 6: Inputs is empty for a source node ───────────────────────────────
ids = [node.Inputs.Id];
assert(isempty(ids), 'Source node should have no input ids');
fprintf('[PASS] Inputs is empty for source node\n');

% ── Test 7: downstream node Inputs contains upstream Id ─────────────────────
downstream = net.addNode(node, sig.OpCode.identity, false);
inputIds = [downstream.Inputs.Id];
assert(any(inputIds == node.Id), ...
    'downstream.Inputs should contain the upstream node Id');
fprintf('[PASS] Inputs of identity node contains upstream id (%d)\n', node.Id);

% ── Test 8: propagation visible via downstream Value ─────────────────────────
affected = net.transact(node, 42.0);
net.apply(affected);
assert(isequal(node.Value, 42.0), 'upstream Value should be 42');
assert(isequal(downstream.Value, 42.0), ...
    'downstream Value should propagate to 42');
fprintf('[PASS] Identity propagation via Value property\n');

% ── Test 9: string value round-trip via Value ─────────────────────────────────
strNode = net.addNode(sig.Node.empty(1, 0), sig.OpCode.nop, false);
net.apply(net.transact(strNode, "world"));
sv = strNode.Value;
assert(isstring(sv) && sv == "world", 'String round-trip via Value');
fprintf('[PASS] String round-trip via Value\n');

% ── Test 10: logical value round-trip via Value ───────────────────────────────
boolNode = net.addNode(sig.Node.empty(1, 0), sig.OpCode.nop, false);
net.apply(net.transact(boolNode, false));
bv = boolNode.Value;
assert(islogical(bv) && bv == false, 'Logical round-trip via Value');
fprintf('[PASS] Logical round-trip via Value\n');

% ── Test 11: multiple sig.Signal objects from addNode are independent ─────────
nodeA = net.addNode(sig.Node.empty(1, 0), sig.OpCode.nop, false);
nodeB = net.addNode(sig.Node.empty(1, 0), sig.OpCode.nop, false);
assert(nodeA.Id ~= nodeB.Id, 'Each addNode call must produce a unique id');
net.apply(net.transact(nodeA, 1.0));
net.apply(net.transact(nodeB, 2.0));
assert(isequal(nodeA.Value, 1.0), 'nodeA should hold 1.0');
assert(isequal(nodeB.Value, 2.0), 'nodeB should hold 2.0');
fprintf('[PASS] Independent nodes have independent values (A=%.4g, B=%.4g)\n', ...
    nodeA.Value, nodeB.Value);

% ── Test 12: nActiveNodes decreases after deleteNode ─────────────────────────
nBefore = net.nActiveNodes();
net.deleteNode(node);
nAfter = net.nActiveNodes();
assert(nAfter == nBefore - 1, ...
    sprintf('Expected nActiveNodes to decrease by 1 (was %d, now %d)', nBefore, nAfter));
fprintf('[PASS] nActiveNodes decreases after deleteNode (%d -> %d)\n', ...
    nBefore, nAfter);

% ── Test 13: sig.Net.Id is a unique uint64 per network ───────────────────────
netA = sig.Net(100);
netB = sig.Net(100);
assert(isa(netA.Id, 'uint64') && isscalar(netA.Id), ...
    'net.Id must be a scalar uint64');
assert(netA.Id ~= netB.Id, ...
    sprintf('Two nets must have distinct Ids (%d vs %d)', netA.Id, netB.Id));
fprintf('[PASS] sig.Net.Id is unique per network (A=%d, B=%d)\n', netA.Id, netB.Id);

% ── All done ─────────────────────────────────────────────────────────────────
fprintf('\n=== All node tests PASSED ===\n');
