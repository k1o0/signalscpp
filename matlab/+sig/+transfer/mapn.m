function [val, valset] = mapn(values, states, f)
% sig.transfer.mapn  MATLAB-side transfer function for mapn / map2 nodes.
%
% [val, valset] = mapn(values, states, f)
%   Gates on ALL inputs having at least a current value (states >= 0) AND at
%   least one input being new this tick (any state == 1).
%
%   values — 1×(N+1) cell: {this_curr, input0_latest, ..., inputN-1_latest}
%   states — 1×(N+1) int8: state flags (-1=unset, 0=current, 1=new-working)
%   f      — function handle applied to all input values (N arguments)
%
% See also sig.transfer.map, sig.transfer.filter, sig.Signal/mapn

    val = []; valset = false;
    input_states = states(2:end);
    if any(input_states < 0);  return; end  % at least one input never fired
    if ~any(input_states == 1); return; end  % no new working value this tick
    val    = f(values{2:end});
    valset = true;
end
