#ifndef __TRANSFERER_H_INCLUDED__
#define __TRANSFERER_H_INCLUDED__

#ifdef SIGNALS_EXPORTS
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif


enum class SIGNALS_API Operation {
    // ── User-supplied callable ────────────────────────────────────────────────
    // Stored on the node as a std::function; covers map / mapn / scan / filter.
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

    // ── MEX/language-specific (implemented in binding layer) ─────────────────
    numel        = 30,
    flattenstruct = 40,

    // ── Pass-through / no-op ─────────────────────────────────────────────────
    identity = 50,
    nop      = 51  // source node — value supplied externally via transact()
};


class SIGNALS_API Transferer {
private:
    enum Operation opCode { Operation::nop };
    bool workingInputChanges{ false };
public:
    Transferer(Operation t_op) { opCode = t_op; };
    Transferer(int t_op) { opCode = static_cast<Operation>(t_op); };
    Transferer() { opCode = Operation::nop; };
    Operation get_op() const noexcept { return opCode; }
};

#endif