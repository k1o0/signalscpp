function seconds = GetSecs(varargin)
% GetSecs  Fallback monotonic timer for environments without the PTB MEX.
%
% Returns seconds elapsed since the first call to GetSecs in this MATLAB
% session. The zero point is arbitrary but stable within the session.

persistent startTick

if nargin > 0
	error('GetSecs:UnsupportedInput', ...
		'This fallback GetSecs implementation does not accept input arguments.');
end

if isempty(startTick)
	startTick = tic;
end

seconds = toc(startTick);
