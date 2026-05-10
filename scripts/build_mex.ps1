<#
.SYNOPSIS
    Build and install the Signals MEX layer (signalsproxy.dll + gateway.mexw64).

.DESCRIPTION
    Builds the CMake project in build_mex/ using Visual Studio 2022 and installs
    the output DLLs into matlab/+libmexclass/+proxy/.

    Machine-specific paths (VS 2022 Community, MATLAB R2025a) are hardcoded
    for this workstation.  For a different machine, update the paths in the
    "Machine-specific paths" section or pass -MatlabRoot / -VsRoot.
    See the README "Building the MEX" section for general instructions.

    IMPORTANT: Close MATLAB before running — Windows locks loaded DLLs and
    the install step will fail if MATLAB is running.

.PARAMETER Config
    Build configuration.  Default: Release.
    Valid values: Release, Debug, RelWithDebInfo.

.PARAMETER Target
    CMake target to build.  Default: signalsproxy.
    Pass 'ALL_BUILD' to build everything (includes gateway).
    Pass 'gateway' to rebuild only the MEX gateway (rarely needed).

.PARAMETER Reconfigure
    Re-run the cmake configure step before building.  Required after editing
    CMakeLists.txt or adding new source files.  Safe to pass at any time —
    cmake configure is idempotent.

.PARAMETER SkipInstall
    Build but skip the cmake install step.  Use when MATLAB is open; copy
    the DLLs from build_mex\<Config>\ manually once MATLAB is closed.

.PARAMETER MatlabRoot
    Override the default MATLAB installation path.
    Default: C:\Program Files\MATLAB\R2025a

.PARAMETER VsRoot
    Override the Visual Studio 2022 installation root.
    Default: C:\Program Files\Microsoft Visual Studio\2022\Community

.EXAMPLE
    # Normal workflow — rebuild signalsproxy and install:
    .\scripts\build_mex.ps1

.EXAMPLE
    # Debug build without installing (MATLAB is still open):
    .\scripts\build_mex.ps1 -Config Debug -SkipInstall

.EXAMPLE
    # Force reconfigure after editing CMakeLists.txt:
    .\scripts\build_mex.ps1 -Reconfigure

.EXAMPLE
    # Rebuild everything (signalsproxy + gateway + core):
    .\scripts\build_mex.ps1 -Target ALL_BUILD
#>

param(
    [ValidateSet('Release', 'Debug', 'RelWithDebInfo')]
    [string]$Config = 'Release',

    [string]$Target = 'signalsproxy',

    [switch]$Reconfigure,

    [switch]$SkipInstall,

    [string]$MatlabRoot = 'C:\Program Files\MATLAB\R2025a',

    [string]$VsRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Derived tool paths — both ship with VS 2022 C++ workload.
# ---------------------------------------------------------------------------
$CMAKE_EXE = "$VsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

# ---------------------------------------------------------------------------
# Repo layout (scripts/ lives one level below the repo root).
# ---------------------------------------------------------------------------
$RepoRoot  = Split-Path $PSScriptRoot -Parent
$BuildDir  = Join-Path $RepoRoot 'build_mex'
$InstallPrefix = Join-Path $RepoRoot 'matlab'

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if (-not (Test-Path $CMAKE_EXE)) {
    Write-Error @"
cmake.exe not found at:
  $CMAKE_EXE

Install the 'Desktop development with C++' workload in Visual Studio 2022
(includes the bundled CMake component).
"@
}

if (-not (Test-Path $MatlabRoot)) {
    Write-Error @"
MATLAB not found at:
  $MatlabRoot

Either install MATLAB R2025a or pass -MatlabRoot with the correct path.
"@
}

# ---------------------------------------------------------------------------
# Configure (first time or when explicitly requested)
# ---------------------------------------------------------------------------
$cacheFile = Join-Path $BuildDir 'CMakeCache.txt'
if ($Reconfigure -or -not (Test-Path $cacheFile)) {
    # Remove the cache so cmake accepts a fresh generator/platform combination.
    if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }

    Write-Host "`n[configure]" -ForegroundColor Cyan
    & $CMAKE_EXE `
        -S $RepoRoot `
        -B $BuildDir `
        -G 'Visual Studio 17 2022' `
        -A x64 `
        -DSIGNALSCPP_BUILD_MEX=ON `
        "-DMatlab_ROOT_DIR=$MatlabRoot" `
        "-DCMAKE_INSTALL_PREFIX=$InstallPrefix"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
$buildArgs = @('--build', $BuildDir, '--config', $Config)
if ($Target -ne 'ALL_BUILD') { $buildArgs += @('--target', $Target) }

Write-Host "`n[build] config=$Config  target=$Target" -ForegroundColor Cyan
& $CMAKE_EXE @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if ($SkipInstall) {
    Write-Host "`n[skip-install] Binaries are in: $BuildDir\$Config\" -ForegroundColor Yellow
    Write-Host "  Copy them to matlab\+libmexclass\+proxy\ once MATLAB is closed." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[install] Copying to: $InstallPrefix" -ForegroundColor Cyan
Write-Host "  If this fails, close MATLAB and re-run." -ForegroundColor Yellow
& $CMAKE_EXE --install $BuildDir --config $Config
if ($LASTEXITCODE -ne 0) {
    Write-Error @"
Install failed — is MATLAB open?
Close MATLAB and re-run, or use -SkipInstall to build without installing.
"@
}

Write-Host "`n[done] Call addSignalsPaths in MATLAB to reload the new binaries." -ForegroundColor Green
