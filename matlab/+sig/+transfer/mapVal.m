function [val, valset] = mapVal(values, states)
% sig.transfer.mapVal  MATLAB-side transfer function for value-map nodes.
%
% [val, valset] = mapVal(values, states)
%   Gates on the first input having a new working value (states(2) == 1)
%   and the second input being set (states(3) >= 0), then returns the
%   current value of the second input directly.
%
%   values — 1×3 cell: {this_curr, src_latest, f_latest}
%   states — 1×3 int8: state flags (-1=unset, 0=current, 1=new-working)
%
% Used by sig.Signal/map when f is a constant node or signal (not a function
% handle).  The C++ equivalent is map_op with two inputs and no callable.
%
% See also sig.transfer.map, sig.transfer.mapn, sig.Signal/map

    val = []; valset = false;
    if states(2) ~= 1; return; end
    if states(3) <  0; return; end
    val = values{3}; valset = true;
end
