function [val, valset] = map(net, inputs, node, f) %#ok<INUSL>
% sig.transfer.map  MATLAB-side transfer function for map nodes.
%
% [val, valset] = map(net, inputs, node, f)
%   Gates on inputs(1) having a new working value, then returns f(wv).
%
%   net    - sig.Net instance
%   inputs - scalar double input node id
%   node   - this node's id (unused; present for uniform signature)
%   f      - function handle to apply to the input value
%
% See also sig.transfer.mapn, sig.transfer.filter, sig.Signal/map

    val = []; valset = false;
    wv = net.getWorkingValue(inputs(1));
    if ~isempty(wv)
        val = f(wv);
        valset = true;
    end
end
