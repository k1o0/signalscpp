% demo_datostim_grating.m
%
% Demonstrates a sinusoidal Gabor grating driven by a Signals network through
% the DatostimProxy.  The animation loop posts only the phase; all downstream
% layer computation (texture build, view matrix) happens inside the network.
% DatostimWindow.draw() reads the current layer values directly in C++ —
% no per-field MATLAB calls in the hot path.
%
% Prerequisites:
%   1. Build the MEX proxy:
%        msbuild build_mex\signalsproxy.vcxproj /p:Configuration=Release
%        msbuild build_mex\INSTALL.vcxproj      /p:Configuration=Release
%   2. Build datostim.dll:
%        .\extern\datostim\build.ps1
%   3. Add MATLAB paths (once per session):
%        addSignalsPaths(false)

%% ── Configuration ─────────────────────────────────────────────────────────────

SCREEN_W    = 960;     % window width  (pixels)
SCREEN_H    = 400;     % window height (pixels)
N_FRAMES    = 200;     % frames to render
PHASE_STEP  = 6;       % grating phase advance per frame (degrees)

SPATIAL_FREQ = 1/15;   % cycles per visual degree
ORIENTATION  = 0;      % grating tilt (degrees)
SIGMA        = [10 10];% Gaussian window width/height (visual degrees)
AZIMUTH      = 0;      % stimulus centre azimuth (visual degrees)
ALTITUDE     = 0;      % stimulus centre altitude (visual degrees)
CONTRAST     = 1.0;
COLOUR       = [1 1 1];% RGB, 0-1

dll_path = fullfile(fileparts(fileparts(which('addSignalsPaths'))), ...
    'extern', 'datostim', 'datostim.dll');

%% ── Build signal graph ────────────────────────────────────────────────────────

net = sig.Net();

% phase_sig is the only signal updated in the loop.
phase_sig = net.origin('phase');
phase_sig.post(0);

% Build a [stencil, grating] struct array from the current phase.
% All other parameters are constants captured in the closure.
layers_sig = phase_sig.map( ...
    @(ph) grating_layers(ph, SPATIAL_FREQ, ORIENTATION, CONTRAST, COLOUR, ...
                         SIGMA, AZIMUTH, ALTITUDE));

% Split the two-element struct array into separate signals so each can be
% registered independently with watchLayer.
stencil_sig = layers_sig.map(@(l) l(1));
grating_sig = layers_sig.map(@(l) l(2));

%% ── Open window and register layers ──────────────────────────────────────────

win = sig.DatostimWindow(net, SCREEN_W, SCREEN_H, dll_path);
win.setBackground(127, 127, 127, 255);
win.setScreen(0, 0, 0, SCREEN_W, SCREEN_H);

% Layer 0: Gaussian alpha stencil; Layer 1: sinusoid grating.
% watchLayer stores the node ID; draw() reads it directly in C++.
win.watchLayer(0, stencil_sig);
win.watchLayer(1, grating_sig);

%% ── Animation loop ────────────────────────────────────────────────────────────

fprintf('Rendering %d frames...\n', N_FRAMES);
t0 = tic;

for frame = 1:N_FRAMES
    % Post the new phase.  This propagates through the network:
    %   phase_sig → layers_sig → stencil_sig, grating_sig
    % After post() returns, all current values are committed.
    phase_sig.post(mod(frame * PHASE_STEP, 360));

    % draw() reads stencil_sig and grating_sig node values directly in C++,
    % converts the MATLAB structs to dstim_layer_* API calls, and presents
    % the frame — no MATLAB callbacks in this path.
    win.draw();
end

elapsed = toc(t0);
fprintf('Done: %.1f ms/frame (%.0f fps)\n', ...
    1000*elapsed/N_FRAMES, N_FRAMES/elapsed);

%% ── Cleanup ───────────────────────────────────────────────────────────────────

win.cleanup();
clear net win

%% ── Layer builder (runs in MATLAB; result cached by the network) ──────────────

function layers = grating_layers(phase_deg, sf, ori_deg, contrast, ...
                                  colour, sigma, az, alt)
% Return a 1×2 struct array [gaussian_stencil, sinusoid_grating].
% Called by the signals map whenever phase_sig fires.

layers = [gaussian_stencil(az, alt, sigma), ...
          sinusoid_grating(phase_deg, sf, ori_deg, contrast, colour, az)];
end

% --------------------------------------------------------------------------

function layer = sinusoid_grating(phase_deg, sf, ori_deg, contrast, colour, az)
% Build the sinusoid grating layer struct.

% 37-sample single-cycle cosine, 0-1 luminance.  37 samples gives <0.5/255
% max linear-interpolation error over a full cycle (same choice as legacy).
np  = 37;
pts = linspace(-0.5, 0.5 - 1/np, np);
img = single(0.5 * cos(2*pi*pts) + 0.5);   % 1×37

% Phase (degrees) → horizontal texture offset (visual degrees)
phase_rad    = phase_deg * pi/180;
phase_offset = phase_rad / (2*pi*sf) + az * cosd(ori_deg);

layer = empty_layer();
layer.texOffset    = [phase_offset; 0];
layer.texAngle     = ori_deg;
layer.size         = [1/sf; 180];   % periodic over full altitude
layer.isPeriodic   = true;
layer.blending     = 'destination';
layer.interpolation = 'linear';
lo = 0.5 - 0.5*contrast;
hi = 0.5 + 0.5*contrast;
layer.minColour    = lo .* [colour(:); 0];
layer.maxColour    = hi .* [colour(:); 1];
layer.show         = true;
[layer.rgba, layer.rgbaSize] = to_rgba(img, 1);
end

% --------------------------------------------------------------------------

function layer = gaussian_stencil(az, alt, sigma)
% Build the Gaussian alpha-stencil layer struct.

% 61-sample unit-sigma Gaussian.  Values at ±3.6σ are <0.5/256, giving
% negligible clipping of the envelope.
xlim = 18/5;
np   = 61;
p    = single(linspace(-xlim, xlim, np));
gauss = exp(-0.5*p.^2)' * exp(-0.5*p.^2);   % 61×61

layer = empty_layer();
layer.texOffset    = [az; alt];
layer.size         = [2*xlim*sigma(1); 2*xlim*sigma(2)];
layer.isPeriodic   = false;
layer.blending     = 'none';
layer.colourMask   = [false; false; false; true]; % alpha channel only
layer.interpolation = 'linear';
layer.show         = true;
[layer.rgba, layer.rgbaSize] = to_rgba(0, gauss);
end

% --------------------------------------------------------------------------

function layer = empty_layer()
% Template layer struct matching the +vis/emptyLayer format expected by
% DatostimProxy::update_layer.
layer.show         = false;
layer.textureId    = [];
layer.pos          = [0; 0];     % azimuth/altitude → view matrix (degrees)
layer.size         = [0; 0];     % visual degrees
layer.viewAngle    = 0;          % degrees
layer.texAngle     = 0;          % degrees
layer.texOffset    = [0; 0];     % visual degrees
layer.isPeriodic   = true;
layer.blending     = 'source';
layer.minColour    = [0; 0; 0; 0];
layer.maxColour    = [1; 1; 1; 1];
layer.colourMask   = [true; true; true; true];
layer.interpolation = 'linear';
layer.rgba         = [];
layer.rgbaSize     = [0 0];
end

% --------------------------------------------------------------------------

function [img, sz] = to_rgba(colour, alpha)
% Convert colour (2D float 0-1 or scalar) and alpha (2D float 0-1 or scalar)
% to a uint8 RGBA column vector and size [w h] matching the vis.rgba format.

h = max(size(colour, 1), size(alpha, 1));
w = max(size(colour, 2), size(alpha, 2));
sz = [w h];

if all(colour(:) <= 1), colour = uint8(round(255 * single(colour)));
else,                   colour = uint8(single(colour)); end
if all(alpha(:)  <= 1), alpha  = uint8(round(255 * single(alpha)));
else,                   alpha  = uint8(single(alpha));  end

% Broadcast scalar or greyscale to RGB
if ~isscalar(colour) && size(colour, 3) == 1
    colour = repmat(colour, [1 1 3]);
end

buf = zeros(h, w, 4, 'uint8');
buf(:,:,1:3) = colour;
buf(:,:,4)   = alpha;
buf = permute(buf, [3 2 1]);   % → 4×w×h (RGBA interleaved, row-major for C)
img = buf(:);                  % uint8 column vector
end
