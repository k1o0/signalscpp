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
node = net.addNode([], 51, false);  % op 51 = nop / source
assert(isa(node, 'sig.Signal'), 'addNode must return a sig.Signal');
fprintf('[PASS] addNode returns sig.Signal\n');

% ── Test 2: sig.Signal.Id is a non-negative numeric scalar ───────────────────
assert(isnumeric(node.Id) && isscalar(node.Id) && node.Id >= 0, ...
    'sig.Signal.Id must be a non-negative numeric scalar');
fprintf('[PASS] sig.Signal.Id = %d\n', node.Id);

% ── Test 3: CurrentValue is [] before any transact ───────────────────────────
v = node.CurrentValue;
assert(isempty(v), 'CurrentValue should be [] before any transact');
fprintf('[PASS] CurrentValue is [] before transact\n');

% ── Test 4: WorkingValue is [] outside a transaction ─────────────────────────
wv = node.WorkingValue;
assert(isempty(wv), 'WorkingValue should be [] outside a transact');
fprintf('[PASS] WorkingValue is [] outside transaction\n');

% ── Test 5: CurrentValue reflects committed value after transact+apply ────────
affected = net.transact(node, 3.14);
net.apply(affected);
v = node.CurrentValue;
assert(isequal(v, 3.14), sprintf('Expected 3.14, got %s', mat2str(v)));
fprintf('[PASS] CurrentValue = %.4g after transact+apply\n', v);

% ── Test 6: InputIds is empty for a source node ───────────────────────────────
ids = node.InputIds;
assert(isempty(ids), 'Source node should have no input ids');
fprintf('[PASS] InputIds is empty for source node\n');

% ── Test 7: downstream node InputIds contains upstream Id ─────────────────────
downstream = net.addNode(node, 50, false);  % op 50 = identity
inputIds = downstream.InputIds;
assert(any(inputIds == node.Id), ...
    'downstream.InputIds should contain the upstream node Id');
fprintf('[PASS] InputIds of identity node contains upstream id (%d)\n', node.Id);

% ── Test 8: propagation visible via downstream CurrentValue ───────────────────
affected = net.transact(node, 42.0);
net.apply(affected);
assert(isequal(node.CurrentValue, 42.0), 'upstream CurrentValue should be 42');
assert(isequal(downstream.CurrentValue, 42.0), ...
    'downstream CurrentValue should propagate to 42');
fprintf('[PASS] Identity propagation via CurrentValue property\n');

% ── Test 9: string value round-trip via CurrentValue ─────────────────────────
strNode = net.addNode([], 51, false);
net.apply(net.transact(strNode, "world"));
sv = strNode.CurrentValue;
assert(isstring(sv) && sv == "world", 'String round-trip via CurrentValue');
fprintf('[PASS] String round-trip via CurrentValue\n');

% ── Test 10: logical value round-trip via CurrentValue ───────────────────────
boolNode = net.addNode([], 51, false);
net.apply(net.transact(boolNode, false));
bv = boolNode.CurrentValue;
assert(islogical(bv) && bv == false, 'Logical round-trip via CurrentValue');
fprintf('[PASS] Logical round-trip via CurrentValue\n');

% ── Test 11: multiple sig.Signal objects from addNode are independent ─────────
nodeA = net.addNode([], 51, false);
nodeB = net.addNode([], 51, false);
assert(nodeA.Id ~= nodeB.Id, 'Each addNode call must produce a unique id');
net.apply(net.transact(nodeA, 1.0));
net.apply(net.transact(nodeB, 2.0));
assert(isequal(nodeA.CurrentValue, 1.0), 'nodeA should hold 1.0');
assert(isequal(nodeB.CurrentValue, 2.0), 'nodeB should hold 2.0');
fprintf('[PASS] Independent nodes have independent values (A=%.4g, B=%.4g)\n', ...
    nodeA.CurrentValue, nodeB.CurrentValue);

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
