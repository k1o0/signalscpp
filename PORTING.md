# Porting status

This file tracks what has been ported from the legacy Rigbox Signals
implementation (`legacy/Rigbox/signals/mexnet-vs/network/network.c` and the
MATLAB layer in `legacy/Rigbox/signals/+sig/`) to the C++ core under
`Signals/`, plus its MEX and pybind11 bindings.

**Update this file as part of any PR that changes port status.** The skill
tells Claude (and future contributors) to consult this file first when asked
"have we ported X?" — if it lies, we waste time.

Status legend: ✅ done · 🟡 in progress · ⚪ not started · ❌ deliberately
out of scope.

---

## Architecture decisions (resolved)

| Decision | Choice | Notes |
|---|---|---|
| C++ standard | C++17 | No compiler-specific extensions in the core. |
| Core dependencies | None on MATLAB or Python | Core must build and test standalone. |
| Value type | `std::variant` (`signals::Value`) | See "Value type" below. |
| Error type | `signals::Error` + subclasses, thrown | Bindings translate to `mexErrMsgIdAndTxt` / Python exceptions. |
| Node references | `NodeId` handles (typed integer) | Never raw `Node*` or `Node` by value across boundaries. |
| Indexing | 0-based in core; convert at MEX boundary | NumPy is already 0-based. |
| Array layout | Row-major in core (1-D for now) | Revisit when 2-D arrays land. |
| String encoding | UTF-8 in core | Bindings convert. |
| Test framework (core) | GoogleTest | Lives in `Signals-Test/`. |
| Build system | CMake | Bindings gated by `-DSIGNALSCPP_BUILD_MEX=ON` / `-DSIGNALSCPP_BUILD_PYTHON=ON`. |

### Value type

Defined in the core as roughly:

```cpp
namespace signals {
  using Value = std::variant<
      std::monostate,         // "no value yet"
      double,                 // MATLAB's default numeric type
      bool,
      std::string,
      std::vector<double>     // 1-D arrays
  >;
}
```

The core owns the value data. The bindings layer is solely responsible for
converting:

- MEX: `Value fromMx(const mxArray*)` / `mxArray* toMx(const Value&)`
- Python: `Value fromPy(py::object)` / `py::object toPy(const Value&)`

Operations on values are implemented with `std::visit` over `Value`. Type
mismatches throw `signals::TypeError` — there is no silent coercion in the
core.

**Future extension (pending need):** zero-copy views from NumPy/MATLAB will
be added as an additional `std::variant` alternative — a non-owning span
plus a type-erased keepalive holding the source-language reference. This
extends the variant; it does not replace the architecture. Do not pre-empt
this — wait for a real use case.

---

## Core (`Signals/`)

### Network and node lifecycle

| Item | Legacy reference | Status | Notes |
|---|---|---|---|
| `signals::Network` class | `network.c` (top-level) | 🟡 | Skeleton exists; uses `Node` by value (must move to handle/slot-map). |
| Network factory / registry (max ~10 networks, indexed by id) | legacy network table | 🟡 | `NetFactory<T>` exists; revisit slot-map design once `Node` storage is fixed. |
| `Node` class with id, inputs, targets, working/current value | `network.c` node struct | 🟡 | Currently stores nested `std::vector<Node> inputs` and `std::set<Node> targets` — must convert to `NodeId`. |
| `NodeId` handle type | implicit (legacy uses int indices) | ⚪ | Introduce as `enum class NodeId : int32_t {};` or similar typed wrapper. |
| `add_node(inputs, op, appendValues)` | `addNode` in `network.c` | 🟡 | Implemented but takes `Node` by value internally; needs handle refactor. |
| `delete_node` | `deleteNode` in `network.c` | ⚪ | Stub commented out in `network.h`. |
| Node destruction / network teardown | `network.c` cleanup paths | 🟡 | `Node::destroy` / `Network::destroy` exist; need audit once `Value` replaces `DataContainer`. |

### Value handling

| Item | Status | Notes |
|---|---|---|
| `signals::Value` (`std::variant`) | ✅ | Defined in `Signals/value.h`. Alternatives: `monostate`, `double`, `bool`, `std::string`, `std::vector<double>`. Replaces `DataContainer` experiment in `datawrapper.h`. |
| `signals::Error`, `signals::TypeError` | ✅ | Defined in `Signals/value.h`; `TypeError` subclasses `Error`. |
| `Value` arithmetic / comparison via `std::visit` | ✅ | Implemented in `Signals/value.cpp`: `add`, `subtract`, `multiply`, `rdivide`, `ldivide`, `gt`, `ge`, `lt`, `le`, `eq`. Scalar broadcast (double↔vector) supported for arithmetic. `eq` additionally handles `bool==bool` and `string==string`. |

### Transaction engine

| Item | Legacy reference | Status | Notes |
|---|---|---|---|
| `transactNode` — propagate update through graph | `network.c` `transactNode` | ⚪ | Stub commented out at the bottom of `network.cpp`. **Highest-risk port for parity bugs** — write parity tests first. |
| Topological propagation order | `network.c` | ⚪ | Must match legacy ordering exactly. |
| Working-value vs. current-value semantics | `network.c` + primer | ⚪ | Re-read `SignalsPrimer.html` before implementing. |
| `appendValues` behaviour | `network.c` | ⚪ | Field exists on `Node`; semantics not yet wired up. |

### Operations (`Transferer` / `Operation`)

| Op | Status | Notes |
|---|---|---|
| `nop`, `identity`, `function` | 🟡 | Enum values defined in `transferer.h`; no implementation yet. |
| Arithmetic: `plus`, `minus`, `mtimes`, `rdivide`, `mdivide` | ⚪ | Needs `Value` first. |
| Comparison: `gt`, `ge`, `lt`, `le`, `eq` | ⚪ | Needs `Value` first. |
| `numel`, `flattenstruct` | ⚪ | Lower priority; defer until basic transactions work. |

### Higher-level signal operators

These live above the transaction engine in the legacy code (`+sig/+node/Signal.m`)
and combinations of nodes. Port after the engine is solid.

| Operator | Status | Notes |
|---|---|---|
| `map` | ⚪ | |
| `scan` | ⚪ | |
| `merge` | ⚪ | |
| `at` | ⚪ | |
| `keepWhen` | ⚪ | |
| `delay` | ⚪ | |
| `subscriptable` | ⚪ | |

---

## MEX bindings (`Signals/mex/`)

| Item | Status | Notes |
|---|---|---|
| CMake target gated on `SIGNALSCPP_BUILD_MEX` | ⚪ | |
| `mxArray` ↔ `Value` conversion | ⚪ | Blocked on `Value`. |
| Network handle passed to MATLAB (opaque) | ⚪ | |
| Error translation (`signals::Error` → `mexErrMsgIdAndTxt`) | ⚪ | |
| 1-based ↔ 0-based index conversion at boundary | ⚪ | |
| Drop-in replacement for legacy `mexnet-vs/network` MEX entry points | ⚪ | The MATLAB-side `+sig/Net.m` should not need to know which backend it's calling. |

---

## Python bindings (`Signals/python/`)

| Item | Status | Notes |
|---|---|---|
| pybind11 module skeleton | ⚪ | |
| `py::object` ↔ `Value` conversion | ⚪ | Blocked on `Value`. |
| Network and Node Python classes | ⚪ | |
| Error translation via pybind11 | ⚪ | |
| NumPy interop (initially copying; zero-copy later) | ⚪ | |

---

## Tests

| Suite | Status | Notes |
|---|---|---|
| GoogleTest harness in `Signals-Test/` | ⚪ | Set up before the next core feature lands. |
| Core unit tests for `Value` and ops | ⚪ | |
| Core unit tests for `Network` lifecycle | ⚪ | |
| Parity test harness — same scenario, legacy MATLAB vs. new binding | ⚪ | Critical for the transaction engine. Drive from MATLAB and pytest. |
| CI configuration | ⚪ | Core build + tests should run without a MATLAB licence. |

---

## Known issues to fix during the next refactor

These are present in the current code and should be addressed when the
relevant area is touched — flagged here so they don't get lost.

1. ~~**`DataContainer` (`datawrapper.h`) to be removed.**~~ **Done.** `signals::Value`
   is implemented in `value.h`/`value.cpp` and is now used throughout
   `network.h`/`network.cpp`. `datawrapper.h` and the empty `datawrapper.cpp`
   remain in the project (they compile without error) but contain no live code.
   They can be deleted from the `.vcxproj` and the filesystem in a follow-up
   cleanup once the PORTING checklist is further along.
2. **MSVC-only `__declspec` macros** in every header. Replace with a
   cross-platform `SIGNALS_API` macro that picks `__declspec` on MSVC
   and `__attribute__((visibility("default")))` on GCC/Clang.
3. **Manual `delete workingValue` / `delete currentValue`** in
   `Node::destroy`. Goes away once `Value` is held by value, not pointer.
4. **`NetFactory` slot reuse.** `destroy` resets the `unique_ptr` but
   leaves the slot in the vector — fine for now, but means ids are
   monotonic and the vector grows. Decide whether to slot-reuse before
   long-running uses.

---

## Out of scope (❌)

- Porting the GUI / experiment-rig wrappers above Signals (`+exp/`,
  `+eui/`, etc.). Signals is the dataflow library; the rig glue stays
  in MATLAB for now.
- Replacing the legacy MATLAB `+sig/` user-facing API. The new MEX
  bindings should be drop-in compatible with the legacy MEX entry
  points so `+sig/` continues to work unchanged.