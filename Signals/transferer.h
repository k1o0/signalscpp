#ifndef __TRANSFERER_H_INCLUDED__
#define __TRANSFERER_H_INCLUDED__

#ifdef SIGNALS_EXPORTS
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif


enum class SIGNALS_API Operation {
    function = 0,
    plus = 1,
    minus = 2,
    mtimes = 3,
    rdivide = 4,
    mdivide = 5,
    gt = 10,
    ge = 11,
    lt = 12,
    le = 13,
    eq = 14,
    numel = 30,
    flattenstruct = 40,
    identity = 50,
    nop = 51 // no operation
};


class SIGNALS_API Transferer {
private:
    enum Operation opCode { Operation::identity };
    bool workingInputChanges{ false };
public:
    Transferer(Operation t_op) { opCode = t_op; };
    Transferer(int t_op) { opCode = static_cast<Operation>(t_op); };
    Transferer() { opCode = Operation::identity; };
};

#endif