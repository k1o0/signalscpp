# Signals — MATLAB layer

This directory contains the MATLAB package `+sig` that wraps the C++
reactive-network backend via the [libmexclass](../extern/libmexclass/) proxy
mechanism.

```
matlab/
  addSignalsPaths.m        — one-call setup (add this file's folder to MATLAB path first)
  +sig/                    — user-facing package (sig.Net, sig.Signal, …)
  +libmexclass/            — libmexclass MATLAB runtime (pre-built, do not edit)
  tests/                   — unit tests (transfer_test.m, node_test.m)
```

---

## Quick start

```matlab
% From the repo root, or any directory that already has this matlab/ folder
% on the MATLAB path, call:
addSignalsPaths;

% Create a network
net = sig.Net();

% Origin signals — the entry points; post values to drive the network
t   = net.origin();   % "time" signal
x   = net.origin();   % "position" signal

% Derive new signals with map / map2 / scan / filter …
speed    = x.map(@(v) v * 10);          % speed = position × 10
inBounds = x.filter(@(v) v >= 0 & v <= 100);
running  = t.scan(@(n, ~) n + 1, 0);   % count ticks of t

% Inspect values after posting
x.post(5);
fprintf('speed = %g\n', speed.CurrentValue);   % → 50

t.post([]);   % any value triggers the scan
t.post([]);
fprintf('ticks = %g\n', running.CurrentValue); % → 2
```

---

## Installation

### Prerequisites

| Requirement | Notes |
|---|---|
| MATLAB R2022b or later | Required for `arguments` blocks and the libmexclass gateway MEX |
| Visual C++ Redistributable 2022 (x64) | The pre-built `.dll` files were compiled with MSVC v143 |

### Steps

1. **Clone the repository** (if not already done):

   ```
   git clone --recurse-submodules <repo-url>
   cd signalscpp
   ```

2. **Add `matlab/` to your MATLAB path** — either via the MATLAB GUI
   (*Home → Set Path → Add Folder*) or by running this once from the
   MATLAB command window:

   ```matlab
   addpath('C:\path\to\signalscpp\matlab');
   savepath;   % optional — persist across sessions
   ```

3. **Call `addSignalsPaths`** at the start of each MATLAB session (or add
   it to your `startup.m`):

   ```matlab
   addSignalsPaths;
   ```

   This adds the pre-built `+libmexclass` proxy runtime and the `+sig`
   package to the path, and loads the gateway MEX.

4. **Verify the installation**:

   ```matlab
   net = sig.Net();
   x   = net.origin();
   y   = x.map(@(v) v.^2);
   x.post(3);
   assert(y.CurrentValue == 9);
   disp('Signals is installed correctly.')
   ```

---

## Running the tests

From the `matlab/` directory (or anywhere with `matlab/` already on the path):

```matlab
cd matlab          % if starting from the repo root
runtests('tests/transfer_test.m')
runtests('tests/node_test.m')
```

All tests should report **Passed**.

---

## Building the MEX

> Skip this section if you are using the pre-built binaries in
> `matlab/+libmexclass/+proxy/`.

The MEX layer is split across two DLLs:

| File | Purpose |
|---|---|
| `gateway.mexw64` | libmexclass dispatch gateway — entry point called by `Proxy.m` |
| `signalsproxy.dll` | Signals C++ proxy implementations (`sig.NetworkProxy`, `sig.NodeProxy`) |

They are built by the **CMake project** in `build_mex/` (pre-configured;
do not confuse with the root `CppSignals.sln` which only builds the C++
unit-test binaries).

### Rebuild and install (after editing C++ source files)

**Close MATLAB first** — Windows locks the loaded DLL and the install step
will fail if MATLAB is open.

From a *Developer Command Prompt for VS 2022* (or any shell that can find
`MSBuild.exe`):

```bat
rem 1. Rebuild signalsproxy.dll (picks up changes in Signals/*.cpp / *.h)
msbuild build_mex\signalsproxy.vcxproj /p:Configuration=Release

rem 2. Install into matlab\+libmexclass\+proxy\  (copies DLL + libs)
cmake -DBUILD_TYPE=Release -P build_mex\cmake_install.cmake
```

Step 2 can also be run as:

```bat
msbuild build_mex\INSTALL.vcxproj /p:Configuration=Release
```

After re-opening MATLAB, call `addSignalsPaths` again — it runs
`clear mex` internally so the freshly installed DLL is loaded on next use.

### Rebuild gateway.mexw64 (rare)

`gateway.mexw64` only needs rebuilding if the libmexclass ABI changes
(practically never).  Build `build_mex\gateway.vcxproj` with
`/p:Configuration=Release`, then run the install step above.

### Running the C++ unit tests

The root `CppSignals.sln` (not the CMake one in `build_mex/`) contains the
`Signals-Test` project (GoogleTest), which tests the C++ core independently
of MATLAB:

```bat
msbuild CppSignals.sln /p:Configuration=Debug /p:Platform=x64
x64\Debug\Signals-Test.exe
x64\Debug\Signals-Test.exe --gtest_filter="TransferTest.*"   rem subset
```

---

## Contributor notes

### Adding a new transfer operation

1. **C++ core** (`Signals/transferer.h`, `Signals/network.cpp`) — add the
   opcode and its `transfer()` implementation, then add GoogleTest coverage
   in `Signals-Test/test.cpp`.

2. **MATLAB binding** — if the operation is purely MATLAB-level (like
   `numel`), add it in `+sig/+node/Signal.m`.  If it requires a new C++
   opcode, expose it through `sig.Net.addNode` with the new opcode number.

3. **Abstract interface** — add the signature to `+sig/Signal.m` (as an
   `abstract` method) so that operator overloads and future alternative
   backends can rely on it.

4. **Tests** — add at least one test in `tests/transfer_test.m`.

5. **`PORTING.md`** — mark the operation ✅ and summarise the design
   decision.

### Class hierarchy overview

```
sig.Signal          (abstract handle)        +sig/Signal.m
  └── sig.node.Signal   (concrete, MEX-backed)   +sig/+node/Signal.m
        └── sig.node.OriginSignal  (adds post)   +sig/+node/OriginSignal.m

sig.Node            (internal MEX shim)      +sig/Node.m
sig.Net             (value class, owns proxy) +sig/Net.m
```

Users see only `sig.Signal` (abstract) and the two concrete subclasses
returned by `sig.Net`.  `sig.Node` is internal.

### `sig.Net` value-class semantics

`sig.Net` is a MATLAB *value* class, not a handle.  The `Proxy` property
it holds is itself a handle (a `libmexclass.proxy.Proxy`), so copies of a
`sig.Net` all share the same underlying C++ network — but standard MATLAB
"copy on assign" semantics apply to the wrapper struct.  Keep `sig.Net`
as a value class: it mirrors the legacy API.
