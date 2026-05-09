---
name: signalscpp-port
description: Use this skill whenever working in the signalscpp repository — porting Rigbox's MATLAB+C "Signals" reactive dataflow library to modern C++ with MATLAB (MEX) and Python (pybind11) bindings. Trigger on any task that touches the legacy code under `legacy/Rigbox/`, the new C++ core, the MEX layer, the Python bindings, or build/test infrastructure for this port. Also trigger when the user mentions Signals, signal nodes, the network/transaction model, MEX networks, or asks about behavior parity between the new C++ implementation and the legacy MATLAB/C version.
---

# signalscpp — Rigbox Signals C++ Port

## What this project is

This repo ports **Rigbox's Signals library** from its original MATLAB + C-MEX implementation to a modern C++17 core with bindings for both MATLAB (via MEX) and Python (via pybind11).

**Signals** is a reactive dataflow / FRP-style system used in neuroscience experiment rigs (originally from the Carandini/Harris labs at UCL). The mental model:

- A **Net** (network) owns a graph of **Nodes**.
- Each node holds a current value and a set of dependencies.
- Operations on signals (map, scan, merge, at, keepWhen, etc.) build new nodes wired into the graph.
- Updates propagate through the graph in **transactions**: when an input node is posted to, all dependent nodes recompute in topological order within one atomic step.
- The legacy C code (`network.c`) is the transaction engine; the MATLAB layer (`+sig/`) is the user-facing API plus glue to MEX.

The port preserves these semantics exactly. Behavior parity with the legacy implementation is the primary correctness criterion.

## Read these first, in this order

When picking up any non-trivial task in this repo, read in order:

1. **`legacy/Rigbox/docs/html/SignalsPrimer.html`**, **`using_signals.html`**, and **`advanced_signals.html`** — the *concept* of Signals. Don't skip these; the C code is unreadable without the model in your head.
2. **`legacy/Rigbox/signals/mexnet-vs/network/network.h`** then **`network.c`** — the legacy transaction engine. The `.c` file is poorly commented; lean on the primer to interpret it.
3. **`legacy/Rigbox/signals/+sig/Net.m`**, then **`+sig/+node/Node.m`**, then **`+sig/+node/Signal.m`** — the MATLAB-facing API. Note which methods are pure MATLAB and which call into MEX.
4. The current state of the C++ port — start with the top-level `CMakeLists.txt` and the public headers in `include/` (or wherever they live; check the tree).

If a piece of legacy behavior is ambiguous, the legacy C code is the ground truth, not the docs.

## Port architecture (current decisions)

- **Language / standard:** C++17, no compiler-specific extensions in the core.
- **Core library:** header-only or static lib at `Signals/`, no MATLAB or Python dependencies. The core must build and test standalone.
- **MEX bindings:** `Signals/mex/` — thin translation layer between MATLAB types and the core. No business logic here.
- **Python bindings:** `Signals/python/` using **pybind11** — same role as MEX, just for Python.
- **Build:** CMake, with options to enable/disable each binding layer (`-DSIGNALSCPP_BUILD_MEX=ON`, `-DSIGNALSCPP_BUILD_PYTHON=ON`).
- **Tests:** Tests in `Signals-Test` using `GoogleTest` for the C++ core; legacy parity tests driven from MATLAB and pytest will live alongside.

## Translation conventions

When porting a legacy construct, follow these rules unless there's a specific reason to deviate (and document the deviation):

- **Naming:** legacy `sig.node.Signal` → `signals::Signal`. Free functions in `network.c` like `addNode`, `transactNode` become methods on `signals::Network`. Keep the legacy name visible in a comment on the new declaration so the mapping is greppable.
- **Memory:** the legacy C code uses raw pointers and ad-hoc lifetime rules. In the port, the `Network` owns its nodes (e.g. `std::vector<std::unique_ptr<Node>>` or a slot-map keyed by node id). External code holds `NodeId` handles, never raw pointers — this matches the legacy "node index" model and survives reallocation.
- **Values:** legacy nodes carry MATLAB `mxArray*`. In the core, use a **`signals::Value`** type defined as a `std::variant` over a small, fixed set of supported types (start with `std::monostate`, `double`, `bool`, `std::string`, `std::vector<double>` — extend deliberately). The core owns the value data. The MEX layer converts `mxArray` ↔ `Value` at the boundary; the Python layer converts `py::object` ↔ `Value` at its boundary. The core must not depend on either. **No `void*`, no abstract `DataContainer` base class, no template parameter on `Node` or `Network` for the value type.** When zero-copy views from NumPy/MATLAB are needed later, add a non-owning variant alternative (e.g. a span plus a type-erased keepalive that holds the source-language reference) — extending the variant, not replacing the architecture.
- **Errors:** the legacy code returns error codes and sometimes calls `mexErrMsgIdAndTxt`. In the C++ core, throw a `signals::Error` (or subclass). The MEX layer catches and translates to `mexErrMsgIdAndTxt`; the Python layer lets pybind11 translate to a Python exception.
- **Transactions:** preserve the exact propagation order of the legacy engine. This is the most likely place for subtle parity bugs — when in doubt, write a parity test before changing anything.

## When writing new code

- New core code goes under the core directory and must not `#include` `mex.h`, `<Python.h>`, or `pybind11/*`. If you find yourself wanting to, you're in the wrong layer.
- Every public core API gets a unit test. Every legacy behavior the user can observe (a method on `Signal` in MATLAB) gets a parity test that runs the same scenario against legacy MATLAB and the new binding and compares results.
- Prefer `constexpr`, `noexcept`, and `[[nodiscard]]` where they're meaningful. Don't sprinkle them performatively.
- Don't reach for templates or `concepts` to mirror MATLAB's dynamic typing — use `signals::Value`. Heavy templating here will hurt build times and binding ergonomics for no semantic gain.
- Operations on values are implemented with `std::visit` over `Value`. Type mismatches throw `signals::TypeError` (a subclass of `signals::Error`); do not silently coerce.

## When asked about port status

The user may ask "have we ported X yet?" Don't guess. Check:

1. The repo's **`PORTING.md`** — the canonical checklist of what's ported, in progress, and pending.
2. The current core headers — if there's no declaration for it, it's not ported.
3. Search the codebase: `grep -r "X" Signals/`.

If the answer isn't clear from the repo, say so and ask the user rather than inventing a status.

## Core concepts and terminology

### Node types

**Origin node**
A network input node: no input nodes, value can be posted/updated any number of times during the life of the network.  In the legacy MATLAB code this is a `sig.node.OriginSignal`, created via `net.origin('name')`.  In the port it is a `nop`-op node (opcode 51) whose value is driven exclusively by `transact()` calls issued from experiment/user code.  Only origin nodes should ever be the target of an external `post` / `transact` call.  The `sig.Node` MATLAB class must **not** expose a mechanism to post to arbitrary non-origin nodes — doing so would corrupt the reactive graph.

**Root node**
A constant source node: no input nodes, value set exactly **once** at construction (as its committed `currentValue`) and never updated again.  In the legacy code, `sig.node.from` creates root nodes automatically when a plain MATLAB value (e.g. the `2` in `y = x + 2`) is used as an input to a derived signal; the factory calls `rootNode(net, name)` and pre-sets `CurrValue`.  In the port, root nodes are created by the `nodeFrom_` / `origin(value)` helpers in `sig.Net`: a `nop` node is made, one `transact`+`apply` is called to commit the constant, and the node is then never transacted again.  Root nodes make the graph purely declarative for constant sub-expressions.

The key rule: **if a node's value must be settable more than once, it is an origin node; if its value is fixed at creation, it is a root node.**

---

### Transaction model

**`transact(node_id, value)`** (C++ `Network::transact`)
Posts a new value to a single source node (always a origin or root node in normal use) and propagates the change through the graph via breadth-first traversal.  Each reachable node calls `transfer()` in topological order.  The result is a list of *affected* node IDs — every node whose working value was set during this pass.  Working values are **not** yet committed; the graph is left in a "pending" state until `apply` is called.  Legacy analogue: `transactNode` / `sqTransact` in `network.c`.

**`apply(affected_ids)`** (C++ `Network::apply`)
Commits working values into current values for all affected nodes, then clears the working values.  Called immediately after `transact` to close the transaction.  Nodes with `appendValues = true` (e.g. `bufferUpTo`) concatenate into the current value rather than replacing it.  After `apply`, the network is back in a stable, committed state.  Legacy analogue: `sqApply` in `network.c`.

Together `transact` + `apply` form one **transaction** — the atomic unit of update in the reactive graph.

---

### Transfer

**Transfer (per-node computation)**
The operation a node performs to compute its output from the working/current values of its inputs.  Called on every node in the BFS frontier of a `transact`.  The C++ method is `Network::Node::transfer()`.  It returns `true` if the node produced a new working value (propagation continues to its targets) or if the node's previously-set working value was cleared (propagation must also continue so downstream nodes learn the value vanished).  Returns `false` if nothing changed.  Legacy analogue: `transfer()` in `network.c`.

**Transfer function (opcode + callable)**
The specific computation rule associated with a node's `Operation` opcode.  Pure-C++ opcodes (e.g. `nop`, `plus`, `merge`, `numel`) are implemented entirely inside `Node::transfer()`.  Higher-order opcodes (`map_op = 60`, `mapn_op = 61`, `filter_op = 62`, `scan_op = 63`) additionally carry a **callable** — a `std::function<signals::Value(inputs, acc)>` — that is set separately after the node is created.  The MEX binding wraps a MATLAB function handle into this callable via `wrap_matlab_*_fn` factories in `mx_ops.cpp`.

---

## Things that are easy to get wrong

- **Silent type coercion.** MATLAB freely coerces between numeric types; the C++ core is explicit. The supported types are exactly the alternatives listed in `signals::Value` — anything else is rejected at the binding boundary.
- **MATLAB's 1-based indexing** vs. C++ 0-based. Convert at the MEX boundary, never inside the core.
- **Working directories.** MEX builds and tests sometimes assume MATLAB's `pwd`. Don't bake path assumptions into the core.
- **Row-major vs. column-major.** MATLAB is column-major, NumPy defaults to row-major. The bindings layer handles this — the core picks one (row-major by default for 1-D vectors; document explicitly when 2-D arrays are added) and documents it.
- **Char encoding.** MATLAB strings, `char16_t`, and Python `str` (UTF-8) are three different things. The core uses **UTF-8** (`std::string` in `Value`); the bindings convert at the edges.
- **Storing Nodes by value.** `Node` instances are owned by the `Network`'s storage and may be reallocated. Internal references between nodes (inputs, targets) must use `NodeId` handles, never `Node` or `Node*`. Copying a `Node` into another container is almost always a bug.

## Out of scope for this skill

This skill does *not* cover: general C++ tutoring, generic CMake advice, Git workflow, or how pybind11 works in the abstract. Claude already knows those. This file is specifically for the conventions, layout, and gotchas of *this* port.
