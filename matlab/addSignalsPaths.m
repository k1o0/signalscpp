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
% The libmexclass gateway MEX (gateway.mex*) and the Signals proxy shared
% library (signalsproxy.*) live in matlab/+libmexclass/+proxy/. They are
% rebuilt by the CMake project in build_mex/ and installed with:
%
%   cmake --build build_mex --config Release --target signalsproxy
%   cmake --install build_mex --config Release
%
% MATLAB must be closed before replacing loaded binaries. Calling
% addSignalsPaths() afterwards forces the proxy to be reloaded from disk.
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
      fullfile(root, 'util'),...
      fullfile(root, 'tests')...
      );
    
    if savePaths
      assert(savepath == 0, 'Failed to save changes to MATLAB path');
    end

    % Release any loaded MEX so the next proxy construction picks up the
    % DLL that is currently on disk (important after a rebuild + install).
    clear mex %#ok<CLMEX>

    fprintf('[Signals] Path configured. %s\n', fullfile(root));
end
