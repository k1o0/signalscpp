function [val, valset] = map(values, states, f)
% sig.transfer.map  MATLAB-side transfer function for map nodes.
%
% [val, valset] = map(values, states, f)
%   Gates on the sole input having a new working value (states(2) == 1),
%   then returns f(input_value).
%
%   values — 1×2 cell: {this_curr, input_latest}
%   states — 1×2 int8: state flags (-1=unset, 0=current, 1=new-working)
%   f      — function handle applied to the input value
%
% See also sig.transfer.mapn, sig.transfer.filter, sig.Signal/map

    val = []; valset = false;
    if states(2) ~= 1; return; end
    val    = f(values{2});
    valset = true;
end
