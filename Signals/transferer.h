#ifndef __TRANSFERER_H_INCLUDED__
#define __TRANSFERER_H_INCLUDED__

#if defined(SIGNALS_STATIC_LIB)
#define SIGNALS_API
#elif defined(SIGNALS_EXPORTS)
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

#include "value.h"
#include <functional>
#include <utility>
#include <vector>

enum class SIGNALS_API Operation {
    // ── User-supplied callable — generic escape hatch ─────────────────────────
    // The callable receives ALL inputs' latest values + currentValue and is
    // entirely responsible for transfer semantics.  Use this opcode when you
    // want to implement a custom transfer function in pure MATLAB:
    //   wrap the MATLAB function in a NodeCallable (see mx_ops.h) and attach
    //   it with set_node_callable().  The node fires whenever any input has a
    //   new working value (same gate as mapn_op).
    //
    // For the common built-in ops (map, filter, scan, numel) prefer the
    // dedicated opcodes 60-63 / 30 so that a future C++ fast-path can be
    // dropped in without changing the MATLAB API.
    // Legacy analogue: the generic sig.transfer path in Signals
    function = 0,

    // ── Arithmetic (binary, element-wise) ────────────────────────────────────
    plus    = 1,
    minus   = 2,
    mtimes  = 3,
    rdivide = 4,
    mdivide = 5,

    // ── Comparison (binary) ──────────────────────────────────────────────────
    gt = 10,
    ge = 11,
    lt = 12,
    le = 13,
    eq = 14,

    // ── Graph-wiring / structural ops (Group 1) ───────────────────────────────
    // merge: first input with a working value wins.
    // Legacy analogue: sig.transfer.merge
    merge = 20,

    // at: gate — fires latest 'what' (working or current) when 'when' has a
    // new truthy working value.  inputs = [what, when].
    // Legacy analogue: sig.transfer.at
    at_op = 21,

    // keep_when: like at but 'when' gate uses latest value (working OR current).
    // inputs = [what, when].
    // Legacy analogue: sig.transfer.keepWhen
    keep_when = 22,

    // latch: SR-style latch.  inputs = [arm, release].  Output is bool.
    // Legacy analogue: sig.transfer.latch
    latch = 23,

    // skip_repeats: suppress output if working value equals current value.
    // Legacy analogue: sig.transfer.skipRepeats
    skip_repeats = 24,

    // select_from: inputs = [index, option0, option1, ...]
    // Fires the selected option's latest value whenever the index or the
    // selected option has a new working value.
    // Legacy analogue: sig.transfer.selectFrom
    select_from = 25,

    // ── Pure-C++ unary op (no callable) ──────────────────────────────────────
    // numel: output = number of elements of the input value.
    //   monostate→0, double/bool/string→1, vector<double>→size.
    //   Implemented directly in Network::Node::transfer(); no callable needed.
    // Legacy analogue: sig.node.Signal/numel
    numel         = 30,

    // flattenstruct: Signal-of-Signal dynamic graph rewiring.
    // NOT YET IMPLEMENTED in transfer().  Reserved for future binding-layer use.
    // Legacy analogue: sig.transfer.flatten / sig.transfer.flattenStruct
    flattenstruct = 40,

    // ── Callable-argument ops (Group 6) ──────────────────────────────────────
    // For these opcodes, Network::Node::transfer() encodes the transfer
    // SEMANTICS (which inputs to gather, how to gate, what to do with the
    // result).  set_node_callable() receives ONLY the user's function — the
    // transfer argument — wrapped for the Value boundary.
    //
    // This mirrors the legacy separation:
    //   sig.transfer.map  — semantics (opcode)
    //   @(x) x*2         — argument  (callable)
    //
    // The binding layer (Signals-Mex/plugins/mx_ops.h) provides factory
    // functions that create the node and attach the wrapped callable.
    //
    // For a pure-C++ implementation of any of these passes, remove the opcode
    // from this group: add transfer() logic that bypasses the callable.

    // map_op: output = fn(input[0]).
    // Gate: fires only when input[0] has a new working value.
    // Callable contract: fn({latest_input}, curr) -> new_value
    // Legacy analogue: sig.transfer.map
    map_op    = 60,

    // mapn_op: output = fn(input[0], …, input[n-1]).
    // Gate: fires when ANY input has a new working value and ALL inputs have
    // at least a current or working value available.
    // Callable contract: fn({latest_0, …, latest_n-1}, curr) -> new_value
    // Legacy analogue: sig.transfer.mapn
    mapn_op   = 61,

    // filter_op: predicate form — passes input[0] through when fn(input[0])
    // is truthy; suppresses output otherwise.
    // Gate: fires only when input[0] has a new working value.
    // Callable contract: fn({working_input}, curr) -> indicator (truthy = pass)
    // Legacy analogue: sig.transfer.filter (predicate form)
    filter_op = 62,

    // scan_op: fold / running accumulator.
    //
    // Input layout (ALL inputs are nodes — see sig.Net.rootNode for constants):
    //   inputs[0]    = item signal    — triggers the fold step
    //   inputs[1]    = seed signal    — resets/initialises the accumulator
    //   inputs[2..n] = extra fn args  — optional; re-triggers evaluation when any fires
    //
    // Firing rules:
    //   • Seed fires only        → output = seed value (accumulator reset)
    //   • Item fires (± seed, ± extras)
    //                            → acc   = seed's working value if seed also fired this
    //                                      tick; else currentValue; else seed's latest
    //                            → output = fn({item, extras…}, acc)
    //   If the seed node has never provided a value (no committed current value
    //   and no working value this tick), fold ticks are suppressed — matching
    //   legacy behaviour.
    //
    // Callable contract: fn({item, extra0, …}, accumulator) → new_accumulator
    // Legacy analogue: sig.transfer.scan
    scan_op   = 63,

    // ── Pass-through / no-op ─────────────────────────────────────────────────
    identity = 50,
    nop      = 51  // source node — value supplied externally via transact()
};


class SIGNALS_API Transferer {
public:
    // Callable type stored on every node that uses a user-supplied function.
    // Matches the legacy transferInMATLAB contract: the callable is responsible
    // for all gating logic and returns a (value, was_set) pair.
    //   inputs   - latest values of the node's inputs (working if set, else current)
    //   current  - this node's committed current value (used as scan accumulator)
    //   node_id  - this node's id; forwarded to MATLAB transfer functions so they
    //              can call back into the network to query other nodes' values
    // Returns std::pair<signals::Value, bool>:
    //   .first   - the new working value (ignored when .second is false)
    //   .second  - true iff .first should be stored as the new working value
    using NodeCallable = std::function<
        std::pair<signals::Value, bool>(
            const std::vector<signals::Value>&,
            const signals::Value&,
            long)>;

    Transferer() : opCode(Operation::nop) {}
    explicit Transferer(Operation t_op) : opCode(t_op) {}
    explicit Transferer(int t_op) : opCode(static_cast<Operation>(t_op)) {}

    Operation get_op() const noexcept { return opCode; }
    void set_callable(NodeCallable fn) { callable_ = std::move(fn); }
    const NodeCallable& get_callable() const noexcept { return callable_; }
    bool has_callable() const noexcept { return static_cast<bool>(callable_); }

private:
    Operation opCode{ Operation::nop };
    bool workingInputChanges{ false };
    NodeCallable callable_;
};

#endif