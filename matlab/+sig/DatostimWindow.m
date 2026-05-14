classdef DatostimWindow < handle
% sig.DatostimWindow  Datostim rendering window driven directly by signal nodes.
%
%   On each call to draw(), the window reads the current values of all
%   registered signal nodes directly in C++ — no MATLAB struct marshaling
%   in the hot path.
%
% USAGE
%   win = sig.DatostimWindow(net, width, height)
%   win = sig.DatostimWindow(net, width, height, dll_path)
%
%   win.watchLayer(layer_idx, signal)   % register a signal as layer source
%   win.draw()                          % push all layers to GPU, swap buffers
%   t   = win.time()                    % elapsed time in seconds
%   win.setBackground(r, g, b, a)       % uint8 or 0-255 doubles
%   win.setScreen(idx, x, y, w, h)      % screen viewport in pixels
%   win.cleanup()                       % close window and free resources
%
% NOTES
%   The signal passed to watchLayer must belong to the same sig.Net as the
%   one used to construct this window.  The layer struct format matches the
%   legacy +vis/emptyLayer template (show, rgba, rgbaSize, pos, viewAngle,
%   texAngle, texOffset, size, isPeriodic, blending, interpolation,
%   minColour, maxColour, colourMask).
%
%   dll_path defaults to the datostim.dll produced by
%   extern/datostim/build.ps1 (located beside this file).
%
% See also sig.Net, TidyHandle

    properties (Access = private)
        Proxy  % libmexclass.proxy.Proxy for sig.DatostimProxy
    end

    methods
        function obj = DatostimWindow(net, width, height, dll_path)
            if nargin < 4
                % Default: datostim.dll built by build.ps1 beside this file.
                % +sig/ → matlab/ → repo root → extern/datostim/
                sig_dir   = fileparts(mfilename('fullpath'));
                repo_root = fileparts(fileparts(sig_dir));
                dll_path  = fullfile(repo_root, 'extern', 'datostim', 'datostim.dll');
            end
            net_handle = net.networkHandle();
            obj.Proxy = libmexclass.proxy.Proxy( ...
                "Name", "sig.DatostimProxy", ...
                "ConstructorArguments", {uint64(net_handle), double(width), ...
                                         double(height), char(dll_path)});
        end

        function watchLayer(obj, layer_idx, signal)
        % watchLayer  Register a signal as the data source for layer layer_idx.
        %   layer_idx — 0-based layer index (uint32 or double)
        %   signal    — sig.Signal whose current value is a layer struct
            if isa(signal, 'sig.Signal')
                node_id = double(signal.Node.Id);
            else
                error('sig:datostim:badArg', 'signal must be a sig.Signal');
            end
            obj.Proxy.WatchLayer(double(layer_idx), node_id);
        end

        function draw(obj)
        % draw  Push all watched layer values to the GPU and present the frame.
            obj.Proxy.Draw();
        end

        function t = time(obj)
        % time  Elapsed time in seconds since the window was opened.
            t = obj.Proxy.GetTime();
        end

        function setBackground(obj, r, g, b, a)
        % setBackground  Set the window background colour (0-255 per channel).
            obj.Proxy.SetBackground(double(r), double(g), double(b), double(a));
        end

        function setScreen(obj, screen_idx, x, y, w, h)
        % setScreen  Configure a screen viewport (all values in pixels, 0-based idx).
            obj.Proxy.SetScreen(double(screen_idx), double(x), double(y), ...
                                double(w), double(h));
        end

        function cleanup(obj)
        % cleanup  Close the window and release resources.
            obj.Proxy.Cleanup();
        end

        function delete(obj)
            try; obj.cleanup(); catch; end
        end
    end
end
