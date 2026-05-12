// mx_ops.cpp — MATLAB boundary wrappers that produce MexNetwork::NodeCallable values.
//
// After the NetworkT<V> refactor, all callables receive and return
// matlab::data::Array directly — no signals::Value conversion in the hot path.

#include "mx_ops.h"
#include "mex_value_traits.h"   // ValueTraits<matlab::data::Array>::has_value

#include "MatlabDataArray.hpp"

#include <vector>

namespace sq::mex_ops {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static matlab::data::Array make_empty() {
    matlab::data::ArrayFactory f;
    return f.createArray<double>({0, 0});
}

// ---------------------------------------------------------------------------
// Boundary wrappers
// ---------------------------------------------------------------------------

MexNetwork::NodeCallable wrap_isequal(MatlabEngine engine)
{
    return [eng = std::move(engine)]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& /*curr*/,
            long /*node_id*/) -> std::pair<matlab::data::Array, bool>
    {
        // inputs = {working_value, current_value}; return (is_equal, true).
        if (inputs.size() < 2) {
            matlab::data::ArrayFactory f;
            return {f.createScalar<bool>(false), true};
        }
        try {
            std::vector<matlab::data::Array> args = {inputs[0], inputs[1]};
            auto results = eng->feval(u"isequal", 1, args);
            if (results.empty()) {
                matlab::data::ArrayFactory f;
                return {f.createScalar<bool>(false), true};
            }
            return {results[0], true};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

MexNetwork::NodeCallable wrap_matlab_fn(matlab::data::Array fn_handle,
                                        MatlabEngine engine)
{
    return [fn = std::move(fn_handle), eng = std::move(engine)]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& /*curr*/,
            long /*node_id*/) -> std::pair<matlab::data::Array, bool>
    {
        if (inputs.empty()) return {make_empty(), false};

        // feval(fn_handle, input0, input1, …) — arrays passed through directly.
        std::vector<matlab::data::Array> args;
        args.reserve(inputs.size() + 1);
        args.push_back(fn);
        for (const auto& v : inputs) args.push_back(v);

        try {
            auto results = eng->feval(u"feval", 1, args);
            if (results.empty()) return {make_empty(), false};
            bool has_val = !results[0].isEmpty();
            return {results[0], has_val};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

MexNetwork::NodeCallable wrap_matlab_scan_fn(matlab::data::Array fn_handle,
                                             MatlabEngine engine)
{
    // Scan convention: feval(fn_handle, accumulator, item, extra0, …)
    // callable receives: inputs = {item, extra0, …}, curr = accumulator
    return [fn = std::move(fn_handle), eng = std::move(engine)]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& curr,
            long /*node_id*/) -> std::pair<matlab::data::Array, bool>
    {
        if (inputs.empty()) return {make_empty(), false};

        std::vector<matlab::data::Array> args;
        args.reserve(inputs.size() + 2);
        args.push_back(fn);
        args.push_back(curr);       // accumulator as first argument
        for (const auto& v : inputs) args.push_back(v);

        try {
            auto results = eng->feval(u"feval", 1, args);
            if (results.empty()) return {make_empty(), false};
            bool has_val = !results[0].isEmpty();
            return {results[0], has_val};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

MexNetwork::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle,
                                          MatlabEngine engine,
                                          std::shared_ptr<MexNetwork> net,
                                          std::vector<long> input_ids)
{
    // fn_handle is a closure @(values, states) sig.transfer.xxx(values, states, f)
    // Builds values cell {curr, input0, ..., inputN-1} and states int8 vector,
    // then invokes: [val, valset] = feval(fn_handle, values, states)
    //
    // states encoding:
    //   -1 = no value at all (never fired and not fired this tick)
    //    0 = current/committed value only (not fired this tick)
    //    1 = new working value this tick
    return [fn  = std::move(fn_handle),
            eng = std::move(engine),
            net = std::move(net),
            ids = std::move(input_ids)]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& curr,
            long /*node_id*/) -> std::pair<matlab::data::Array, bool>
    {
        const size_t n = inputs.size();
        matlab::data::ArrayFactory f;

        // values cell: {curr, input0, ..., inputN-1}
        auto values = f.createCellArray({1, n + 1});
        values[0] = curr;
        for (size_t i = 0; i < n; ++i)
            values[i + 1] = inputs[i];

        // states int8
        using Traits = ValueTraits<matlab::data::Array>;
        auto states = f.createArray<int8_t>({1, n + 1});
        states[0] = Traits::has_value(curr) ? int8_t(0) : int8_t(-1);
        for (size_t i = 0; i < n; ++i) {
            if (!Traits::has_value(inputs[i])) {
                states[i + 1] = int8_t(-1);
            } else if (Traits::has_value(net->get_working_value(ids[i]))) {
                states[i + 1] = int8_t(1);
            } else {
                states[i + 1] = int8_t(0);
            }
        }

        try {
            std::vector<matlab::data::Array> args = {fn, values, states};
            auto results = eng->feval(u"feval", 2, args);
            if (results.size() < 2) return {make_empty(), false};
            matlab::data::TypedArray<bool> valset_arr = results[1];
            if (!bool(valset_arr[0])) return {make_empty(), false};
            return {results[0], true};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

} // namespace sq::mex_ops
