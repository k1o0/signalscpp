function [val, valset] = filter(values, states, f)
% sig.transfer.filter  MATLAB-side transfer function for filter nodes.
%
% [val, valset] = filter(values, states, f)
%   Passes through the 'what' input when f(what) equals the criterion.
%   Always assumes two inputs in order: [what, criterion].
%
%   values — 1×3 cell: {this_curr, what_latest, criterion_latest}
%   states — 1×3 int8: state flags (-1=unset, 0=current, 1=new-working)
%   f      — function handle applied to what; output compared to criterion
%
% See also sig.transfer.map, sig.transfer.mapn, sig.Signal/filter

    val = []; valset = false;
    if states(3) < 0;  return; end  % criterion never set
    if states(2) ~= 1; return; end  % no new 'what' value this tick

    try
        indicator = f(values{2});
        if isequal(indicator, values{3})
            val    = values{2};
            valset = true;
        end
    catch ex
        rethrow(ex)
    end
end
