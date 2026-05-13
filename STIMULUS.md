# Signals Visual Stimulus

This file tracks the development of a new visual stimulus engine in Signals.

## Legacy stimulus code

Previously there were two visual stimulus engines, one implemented in Java and used for prototyping experiments (`legacy/signals/java/`) and one implemented in Psychtoolbox (see `legacy/signals/+vis/test.m`).

Both of these implementations do not work in recent versions of MATLAB.

## New engine

Now stimulus rendering will take place in a new package called datostim (https://github.com/cortex-lab/datostim/tree/main) using datoviz (https://github.com/datoviz/datoviz), an API built on Vulkan. This is currently in alpha and the main scope for us is to implement the representation of texture layers as signals objects.

## Architecture

In signals, visual stimulus objects are represented as one or more texture layers with a set of fixed parameters passed to the shader. The Signals stimuli are SubscriptableSignals objects.

### Stimulus Signals

The stimulus Signals are in `legacy/signals/+vis/`:

- `checker.m` - checkerboard stimulus
- `grating.m` - 2D sine or square grating, optionally with a Gaussian window
- `grid.m` - perpendicular lines forming a grid
- `image.m` - an image, optionally with a Gaussian window
- `patch.m` - a shape such as a triangle, square, or circle


### Stimulus layers

These stimulus Signals are simply sets of parameters that update a set of layer structs that are passed to the shader. These layers are also in `legacy/signals/+vis/`:

- `emptyLayer.m` - the template texture layer
- `circLayer.m` - texture layer for a circle
- `crossLayer.m` - texture layer for a cross (e.g. X or + shape)
- `gaussianLayer.m` - texture layer for a Gaussian window
- `rectLayer.m` - texture layer for a rectangle or square shape
- `sinosoidLayer.m` - texture layer for a 2D sinewave
- `squareWaveLayer.m` - texture layer for a 2D squarewave

### Experiment workflow

During the main loop of an experiment:

1. the code checks that the window is ready (the previous textures have been rendered and drawn)
2. it gathers all the texture layers (these have been updated by the stimulus Signal objects which contain these updated texture structs are their node's current value)
3. it calls `+vis/draw.m` to pass this to the shader and draw to the screen

### Documentation

The documentation in scanty but can be found in the following files in `legacy/docs/html/`:

- `visual_stimuli.html` - examples of various stimulus Signals
- `using_visual_stimuli.html` - some notes on the visual stimulus implementation

## Building and running the datostim example

The datostim example (`extern/datostim/datostim.c`) renders a Gabor grating on a sphere using Vulkan. It requires three one-time installs, then builds with a single PowerShell script.

### Prerequisites

All three tools need to be installed once. Open PowerShell and run:

```powershell
# C compiler (MinGW-w64 with POSIX threads, UCRT runtime)
winget install BrechtSanders.WinLibs.POSIX.UCRT

# Vulkan SDK — provides glslc.exe for shader compilation
winget install KhronosGroup.VulkanSDK

# Datoviz runtime — provides libdatoviz.dll and all Vulkan/GLFW/ImGui dependencies
pip install datoviz
```

After installing WinLibs and the Vulkan SDK, open a **new** PowerShell window so the updated `PATH` is picked up.

### Build

From the repo root or from `extern/datostim/`:

```powershell
.\extern\datostim\build.ps1
```

The script will:

1. Compile the four GLSL shaders to SPIR-V (skips if already up to date).
2. Generate `libdatoviz.lib` from the pip-wheel DLL (once only).
3. Compile `datostim.c` against `libdatoviz.dll` and the Datoviz headers.

Output: `extern/datostim/datostim.exe`

### Run

```powershell
.\extern\datostim\build.ps1 -Run
```

Or run directly after building (the DLL directories must be on `PATH`):

```powershell
$env:PATH = "$(python -c 'import datoviz,os;print(os.path.dirname(datoviz.__file__))');$env:PATH"
Set-Location extern\datostim
.\datostim.exe
```

The window shows a sinusoid grating with Gaussian stencil projected onto a sphere, split across three simulated screens. The grating phase animates with the timer; the coloured square in the corner toggles each frame.

### What was installed and where

| Tool | winget/pip ID | Default install path |
|------|--------------|----------------------|
| WinLibs gcc 16 | `BrechtSanders.WinLibs.POSIX.UCRT` | `%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.*\mingw64\bin\` |
| Vulkan SDK 1.4 | `KhronosGroup.VulkanSDK` | `C:\VulkanSDK\<version>\Bin\glslc.exe` |
| datoviz 0.3.x | `pip install datoviz` | `%LOCALAPPDATA%\Programs\Python\Python312\Lib\site-packages\datoviz\` |

cglm headers (header-only math library) are downloaded automatically by `build.ps1` from GitHub into `extern/datostim/cglm_include/` if not already present.

## Tasks

- For performance, the stimulus signals should pass their layers directly to the datostim C API without having to return control to MATLAB