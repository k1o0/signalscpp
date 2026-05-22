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
| Node references | `Node*` pointers for internal graph wiring (`inputs`/`targets`); `long` IDs for the public API (`add_node`, `transact`, `get_current_value`) | `NodeId` typed-int wrapper was considered but rejected in favour of stable `Node*` pointers — safe because the `nodes` vector is reserved at construction and never reallocates. External callers still use plain `long` IDs at the public boundary. |
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
| `signals::Network` class | `network.c` (top-level) | ✅ | Core class exists with `add_node`, `transact`, `apply`, `get_current_value`. `NetFactory<Network>` manages up to 10 instances. |
| Network factory / registry (max ~10 networks, indexed by id) | legacy network table | ✅ | `NetFactory<T>` with `create`, `destroy`, `destroy_all`, `is_valid`. Slot reuse not implemented (IDs are monotonic — see known issue #4). |
| `Node` class with id, inputs, targets, working/current value | `network.c` node struct | ✅ | `inputs` and `targets` are `std::vector<Node*>` pointing into the reserved `nodes` vector. Working and current values are `signals::Value`. |
| `NodeId` handle type | implicit (legacy uses int indices) | ❌ | Not introduced — `Node*` pointers used internally; `long` for the public API. See architecture decision above. |
| `add_node(inputs, op, appendValues)` | `addNode` in `network.c` | ✅ | Implemented; validates input IDs, wires targets on input nodes. |
| `delete_node` | `deleteNode` in `network.c` | ✅ | Disconnects node from its inputs' `targets` sets and its targets' `inputs` vectors, then calls `Node::destroy()`. |
| Callable slot (`std::function`) on `Node` | — | ✅ | `Node::callable` stores `f(inputs, current_value) → Value` for `Operation::function` nodes. Set via `Network::set_node_callable(id, fn)`. Returning `monostate` suppresses output that tick. Cleared on `destroy()`. |
| Node destruction / network teardown | `network.c` cleanup paths | ✅ | `Node::destroy` resets all fields and clears pointer vectors, releases callable. `Network::destroy` delegates to `NetFactory`. No manual `delete` (values held by value). |

### Value handling

| Item | Status | Notes |
|---|---|---|
| `signals::Value` (`std::variant`) | ✅ | Defined in `Signals/value.h`. Alternatives: `monostate`, `double`, `bool`, `std::string`, `std::vector<double>`. Replaces `DataContainer` experiment in `datawrapper.h`. |
| `signals::Error`, `signals::TypeError` | ✅ | Defined in `Signals/value.h`; `TypeError` subclasses `Error`. |
| `Value` arithmetic / comparison via `std::visit` | ✅ | Implemented in `Signals/value.cpp`: `add`, `subtract`, `multiply`, `rdivide`, `ldivide`, `gt`, `ge`, `lt`, `le`, `eq`. Scalar broadcast (double↔vector) supported for arithmetic. `eq` additionally handles `bool==bool` and `string==string`. |
| `is_truthy(Value)` | ✅ | Inline helper in `value.h`. `monostate`→false, `bool` as-is, `double`≠0→true, non-empty string→true, `vector<double>` truthy if any element ≠ 0. |
| `values_equal(Value, Value)` | ✅ | Exported function in `value.h`/`value.cpp`. Type-index mismatch → false; `vector<double>` uses element-wise comparison. |

### Transaction engine

| Item | Legacy reference | Status | Notes |
|---|---|---|---|
| `Network::transact(node_id, value)` — propagate update through graph | `network.c` `transact` + `sqTransact` | ✅ | BFS from seed node using `Node::queued` flag to deduplicate. Returns `std::vector<long>` of affected node IDs. |
| `Network::apply(affected_ids)` — commit working → current | `network.c` `sqApply` | ✅ | Moves `workingValue` into `currentValue` for each affected node; resets working to monostate. When `appendValues` is true, concatenates onto a `vector<double>` accumulator instead of replacing. |
| `Node::transfer()` — recompute working value from inputs | `network.c` `transfer` | ✅ | Dispatches on `Operation` enum; uses `LATEST_VALUE` semantics (working preferred over current). Clears working and propagates if output becomes unset. |
| Topological propagation order | `network.c` | ✅ | BFS queue matches legacy `QUEUE_PUT_ALL` / `QUEUE_GET` ordering. |
| Working-value vs. current-value semantics | `network.c` + primer | ✅ | Implemented: `transact` sets working; `apply` commits to current; bindings call both. |
| `appendValues` behaviour | `network.c` | ✅ | `Node::appendValues` flag wired into `apply()`. In the standalone core this appends numeric values into `vector<double>`. In the MATLAB MEX binding it additionally appends struct log records, enabling `sig.Signal.log()` to accumulate `[time, value]` history. |

### Operations (`Transferer` / `Operation`)

| Op | Status | Notes |
|---|---|---|
| `nop`, `identity` | ✅ | `nop`: source nodes — `transact` sets their value directly, `transfer` is never called on them. `identity`: passes first input's working value through. |
| `function` (map / mapn / scan / filter) | ✅ | Invokes `Node::callable(latest_inputs, current_value) → Value` when any input has a new working value. Returning `monostate` suppresses output. Used by binding layers to implement `map`, `mapn`, `scan`, `filter`. |
| Arithmetic: `plus`, `minus`, `mtimes`, `rdivide`, `mdivide` | ✅ | Implemented in `value.cpp` and wired into `Node::transfer()`. Scalar broadcast (double↔vector) supported. |
| Comparison: `gt`, `ge`, `lt`, `le`, `eq` | ✅ | Implemented in `value.cpp` and wired into `Node::transfer()`. |
| `merge` | ✅ | First input with a new working value wins. Mirrors `+sig/+transfer/merge.m`. |
| `at_op` | ✅ | Gate: fires latest `what` (working or current) when `when` has a **new truthy** working value. Mirrors `+sig/+transfer/at.m`. |
| `keep_when` | ✅ | Gate: fires new `what` working value when the latest `when` (working or current) is truthy. Mirrors `+sig/+transfer/keepWhen.m`. |
| `latch` | ✅ | SR-style latch — inputs `[arm, release]`, output `bool`. `release` wins when both fire in the same tick. Mirrors `+sig/+transfer/latch.m`. |
| `skip_repeats` | ✅ | Suppresses output when the new working value equals the current value (`values_equal`). Passes through on the first value. Mirrors `+sig/+transfer/skipRepeats.m`. |
| `select_from` | ✅ | inputs `[index, option0, option1, …]`. Fires the selected option's latest value when the index or the selected option has a new working value. **0-based** (MATLAB `.m` file is 1-based — convert at MEX boundary). Mirrors `+sig/+transfer/selectFrom.m`. |
| `numel`, `flattenstruct` | ⚪ | Language-specific; implemented in binding layer. Opcodes reserved as placeholders. |

### Higher-level signal operators

These live above the transaction engine in the legacy code (`+sig/+node/Signal.m`)
and combinations of nodes. Port after the engine is solid.

| Operator | Status | Notes |
|---|---|---|
| `map` | ✅ | Via `Operation::function` + `set_node_callable`. Binding wraps the user function; core drives timing. |
| `mapn` | ✅ | Same as `map` with multiple inputs; callable receives all latest input values. |
| `scan` | ✅ | Via `Operation::function`; callable receives `current_value` as accumulator seed. |
| `filter` | ✅ | Via `Operation::function`; callable returns `monostate` to suppress, or the input to pass through. |
| `merge` | ✅ | `Operation::merge` in core. |
| `at` | ✅ | `Operation::at_op` in core. |
| `keepWhen` | ✅ | `Operation::keep_when` in core. |
| `latch` | ✅ | `Operation::latch` in core. |
| `skipRepeats` | ✅ | `Operation::skip_repeats` in core. |
| `selectFrom` | ✅ | `Operation::select_from` in core (0-based; convert at MEX boundary). |
| `bufferUpTo` / `buffer` | 🟡 | `appendValues` flag now wired in `apply()`; the higher-level node creation logic (limiting buffer size, etc.) is not yet ported. |
| `delay` | ⚪ | Requires timer integration. |
| `subscriptable` | ⚪ | MATLAB-specific `subsref` forwarding; defer to MEX binding layer. |

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
| GoogleTest harness in `Signals-Test/` | ✅ | Building and running. |
| Core unit tests for `Network` lifecycle | ✅ | `TestConstructor`, `TestNodeCreation`, `ExceedMaxNodes`, `ExceedMaxNetworks`. |
| Core unit tests for `transact` / `apply` | ✅ | `TestTransact`: posts to source nodes, checks downstream recomputation. |
| Core unit tests for `Value` and ops | ✅ | 21 tests in `test_value.cpp`: `has_value`, `type_name`, all 5 arithmetic ops (scalar/vector/broadcast/TypeError), all 5 comparison ops (scalar/vector/bool/string/TypeError). |
| Parity test harness — same scenario, legacy MATLAB vs. new binding | ⚪ | Critical for the transaction engine. Drive from MATLAB and pytest. |
| CI configuration | ⚪ | Core build + tests should run without a MATLAB licence. |

---

## MATLAB Proxies

The MATLAB proxy classes should follow the `+sig/+node/` package in the legacy code as closely as possible.

- The MATLAB implementations of the transfer functions should be copied closely. The signature of transfer functions should be identical for all functions: (net, inputs, node, f).
- The naming of variables in these class methods, e.g. `this` instead of `obj`, and informative
  input names for each method, e.g. `what`, `when`, `criterion`, etc.


---

## Documentation & Code style

Every MATLAB function, method, and class property should come with a complete documentation string.
Functions and methods should have the following format:

```matlab
      %NAME One-line description of function
      % A longer explanation of the function spanning multiple lines
      %
      % Inputs (Optional Name-Value Parameters):
      %   inputArgName (logical) - Explanation of the input argument, its
      %     default, etc.
      %
      % Example:
      %   foo = Bar.baz(x, y, z);
      %
      % See also ETC
```

Class properties should be documentated with a comment above each property.
MATLAB indentations should be 4 spaces.
Variable names should be copied closely from those in the legacy code.

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
2. ~~**MSVC-only `__declspec` macros** in every header.~~ **Done.**
   Shared `Signals/signals_api.h` now defines `SIGNALS_API` cross-platform:
   empty for static builds, `__declspec(...)` on Windows, and
   `__attribute__((visibility("default")))` on GCC/Clang.
3. ~~**Manual `delete workingValue` / `delete currentValue`** in
   `Node::destroy`.~~ **Done.** Resolved when `DataContainer*` was replaced
   by `signals::Value` (held by value, not pointer).
4. **`NetFactory` slot reuse.** `destroy` resets the `unique_ptr` but
   leaves the slot in the vector — fine for now, but means ids are
   monotonic and the vector grows. Decide whether to slot-reuse before
   long-running uses.
5. **Signals** used to be called **Squeak**: references to 'squeak' and 'sq'
   should be renamed to 'signals' and 'sig'.
6. Flattened struct signals can update without all input value availiable.
   See https://github.com/cortex-lab/Rigbox/issues/275

---

## Out of scope (❌)

- Porting the GUI / experiment-rig wrappers above Signals (`+exp/`,
  `+eui/`, etc.). Signals is the dataflow library; the rig glue stays
  in MATLAB for now.
- Replacing the legacy MATLAB `+sig/` user-facing API. The new MEX
  bindings should be drop-in compatible with the legacy MEX entry
  points so `+sig/` continues to work unchanged.

  ---

  ## Summary of method implementation

| Method | MEX | transfer f checked | test | docstring | perf test |
|---|---|---|---|---|---|
| keepWhen | Y | Y | Y |  |  |
| scan |  |  |  |  |  |
| skipRepeats |  |  |  |  |  |
| filter |  |  |  |  |  |
| iff |  |  |  |  |  |
| cond |  |  |  |  |  |
| selectFrom |  |  |  |  |  |
| indexOfFirst |  |  |  |  |  |
| map |  |  |  |  |  |
| map2 |  |  |  |  |  |
| mapn |  |  |  |  |  |
| at |  |  |  |  |  |
| then |  |  |  |  |  |
| subscriptable |  |  |  |  |  |
| buffer |  |  |  |  |  |
| bufferUpTo |  |  |  |  |  |
| delta |  |  |  |  |  |
| lag |  |  |  |  |  |
| to |  |  |  |  |  |
| setTrigger |  |  |  |  |  |
| setEpochTrigger |  |  |  |  |  |
| merge |  |  |  |  |  |
| delay |  |  |  |  |  |
| identity |  |  |  |  |  |
| flatten |  |  |  |  |  |
| flattenStruct |  |  |  |  |  |
| output |  |  |  |  |  |
| onValue |  |  |  |  |  |
| into |  |  |  |  |  |
| valueChanged |  |  |  |  |  |