function [val, valset] = keepWhen(values, states, gate_node)
% sig.transfer.keepWhen  MATLAB-side transfer function for keepWhen nodes.
%
% [val, valset] = keepWhen(values, states, gate_node)
%   Gates on the input having a new working value (states(2) == 1) and
%   gate_node.Value being non-empty and truthy, then passes through the
%   input value unchanged.
%
%   values    — 1×2 cell: {this_curr, input_latest}
%   states    — 1×2 int8: state flags (-1=unset, 0=current, 1=new-working)
%   gate_node — sig.Node sampled lazily; its Value gates whether output fires
%
% See also sig.transfer.filter, sig.transfer.map, sig.Signal/keepWhen

    val = []; valset = false;
    if states(2) ~= 1; return; end
    g = gate_node.Value;
    if isempty(g) || ~g(1); return; end
    val = values{2}; valset = true;
end
