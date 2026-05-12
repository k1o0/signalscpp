function c = pack_outputs(f, nout, varargin)
%PACK_OUTPUTS  Call f with varargin, collect nout outputs into a cell.
%   Used by sig.Signal/mapn for multi-output functions.
c = cell(1, nout);
[c{:}] = f(varargin{:});
end
