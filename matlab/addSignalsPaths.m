function addSignalsPaths(repoRoot)
% addSignalsPaths  Add all Signals MATLAB dependencies to the search path.
%
%   addSignalsPaths()
%       Infers the repository root from this file's location
%       (matlab/addSignalsPaths.m → repo root is the parent directory).
%
%   addSignalsPaths(repoRoot)
%       Explicit repository root path; useful when calling from a
%       different working directory.
%
% After this function returns the following are on the MATLAB path:
%   • matlab/          — +sig package and +libmexclass proxy runtime
%
% The libmexclass gateway MEX (gateway.mexw64) and the Signals proxy
% (signalsproxy.dll) live in matlab/+libmexclass/+proxy/.  They are
% rebuilt by the CMake project in build_mex/ and installed with:
%
%   msbuild build_mex\signalsproxy.vcxproj /p:Configuration=Release
%   msbuild build_mex\INSTALL.vcxproj      /p:Configuration=Release
%
% MATLAB must be closed before running the INSTALL step (Windows locks
% loaded DLLs).  Calling addSignalsPaths() afterwards forces the reloaded
% DLL to be picked up fresh.
%
% Example — add to startup.m:
%   addSignalsPaths('C:\repos\signalscpp');
%
% Example — when already in the matlab/ directory:
%   addSignalsPaths;
%
% See also sig.Net, sig.node.OriginSignal

    if nargin < 1
        % This file lives at <repo>/matlab/addSignalsPaths.m
        thisDir  = fileparts(mfilename('fullpath'));
        repoRoot = fileparts(thisDir);
    end

    matlabDir = fullfile(repoRoot, 'matlab');

    if ~isfolder(matlabDir)
        error('sig:addSignalsPaths:notFound', ...
            ['Could not find the matlab/ directory under:\n  %s\n' ...
             'Check the repoRoot argument or that the working directory is correct.'], ...
            repoRoot);
    end

    % Release any loaded MEX so the next proxy construction picks up the
    % DLL that is currently on disk (important after a rebuild + install).
    clear mex %#ok<CLMEX>

    addpath(matlabDir);

    fprintf('[Signals] Path configured. matlab/ → %s\n', matlabDir);
end
