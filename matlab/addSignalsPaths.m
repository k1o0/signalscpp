function addSignalsPaths(savePaths)
% addSignalsPaths  Add all Signals MATLAB dependencies to the search path.
%
%   addSignalsPaths()
%       Infers the repository root from this file's location and saves
%       paths.
%
%   addSignalsPaths(false)
%       Add paths without saving.
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
% See also sig.Net, sig.OriginSignal

    if nargin < 1
      savePaths = true;
    end
    
    root = fileparts(mfilename('fullpath'));
    
    addpath(...
      root,...
      fullfile(root, 'util')...
      );
    
    if savePaths
      assert(savepath == 0, 'Failed to save changes to MATLAB path');
    end

    % Release any loaded MEX so the next proxy construction picks up the
    % DLL that is currently on disk (important after a rebuild + install).
    clear mex %#ok<CLMEX>

    fprintf('[Signals] Path configured. %s\n', fullfile(root));
end
