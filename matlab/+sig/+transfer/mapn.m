function [val, valset] = mapn(net, inputs, node, f) %#ok<INUSL>
% sig.transfer.mapn  MATLAB-side transfer function for mapn / map2 nodes.
%
% [val, valset] = mapn(net, inputs, node, f)
%   Gates on at least one input having a new working value AND all inputs
%   having at least a current or working value (otherwise output is
%   suppressed: not yet enough information to evaluate f).
%
%   net    - sig.Net instance
%   inputs - row vector of input node ids
%   node   - this node's id (unused; present for uniform signature)
%   f      - function handle applied to all input values
%
% See also sig.transfer.map, sig.transfer.filter, sig.Signal/mapn

    val = []; valset = false;
    vals = cell(1, numel(inputs));
    any_new = false;
    for k = 1:numel(inputs)
        wv = net.getWorkingValue(inputs(k));
        if ~isempty(wv)
            vals{k} = wv;
            any_new = true;
        else
            cv = net.getCurrentValue(inputs(k));
            if isempty(cv), return; end  % input never set — suppress
            vals{k} = cv;
        end
    end
    if any_new
        val = f(vals{:});
        valset = true;
    end
end
