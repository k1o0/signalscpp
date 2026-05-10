// mx_ops.cpp — MATLAB boundary wrappers that produce NodeCallable values.
//
// See mx_ops.h for usage.

#include "mx_ops.h"
#include "mx_convert.h"   // sq::mex::toMda / fromMda

#include "MatlabDataArray.hpp"

#include <vector>

namespace sq::mex_ops {

// ---------------------------------------------------------------------------
// Boundary wrappers
// ---------------------------------------------------------------------------

Network::NodeCallable wrap_matlab_fn(matlab::data::Array fn_handle, MatlabEngine engine)
{
    // Capture fn_handle + engine by value (shared ownership).
    // Called by the core during transact as:
    //   callable({latest(input[0]), ...}, currentValue)
    // We forward all inputs to MATLAB but ignore currentValue.
    return [fn = std::move(fn_handle), eng = std::move(engine)]
           (const std::vector<signals::Value>& inputs,
            const signals::Value& /*curr*/,
            long /*node_id*/) -> std::pair<signals::Value, bool>
    {
        if (inputs.empty()) return {{}, false};

        matlab::data::ArrayFactory f;
        // feval(fn_handle, arg0, arg1, …)
        std::vector<matlab::data::Array> args;
        args.reserve(inputs.size() + 1);
        args.push_back(fn);
        for (const auto& v : inputs)
            args.push_back(sq::mex::toMda(v, f));

        try {
            auto results = eng->feval(u"feval", 1, args);
            if (results.empty()) return {{}, false};
            auto val = sq::mex::fromMda(results[0]);
            return {val, signals::has_value(val)};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

Network::NodeCallable wrap_matlab_scan_fn(matlab::data::Array fn_handle, MatlabEngine engine)
{
    // Capture fn_handle + engine by value.
    // Called by the core during transact as:
    //   callable({item, extra0, …}, accumulator)
    // Scan convention: feval(fn_handle, accumulator, item, extra0, …)
    return [fn = std::move(fn_handle), eng = std::move(engine)]
           (const std::vector<signals::Value>& inputs,
            const signals::Value& curr,
            long /*node_id*/) -> std::pair<signals::Value, bool>
    {
        if (inputs.empty()) return {{}, false};

        matlab::data::ArrayFactory f;
        std::vector<matlab::data::Array> args;
        args.reserve(inputs.size() + 2);   // fn + acc + all inputs
        args.push_back(fn);
        args.push_back(sq::mex::toMda(curr, f));       // accumulator (first arg)
        for (const auto& v : inputs)
            args.push_back(sq::mex::toMda(v, f));      // item, then extras

        try {
            auto results = eng->feval(u"feval", 1, args);
            if (results.empty()) return {{}, false};
            auto val = sq::mex::fromMda(results[0]);
            return {val, signals::has_value(val)};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

Network::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle,
                                       MatlabEngine engine,
                                       std::shared_ptr<Network> net,
                                       std::vector<long> input_ids)
{
    // fn_handle is a closure @(values, states) sig.transfer.xxx(values, states, customArg)
    // Builds values cell {curr, input0, ..., inputN-1} and states int8 vector,
    // then invokes: [val, valset] = feval(fn_handle, values, states)
    return [fn  = std::move(fn_handle),
            eng = std::move(engine),
            net = std::move(net),
            ids = std::move(input_ids)]
           (const std::vector<signals::Value>& inputs,
            const signals::Value& curr,
            long /*node_id*/) -> std::pair<signals::Value, bool>
    {
        const size_t n = inputs.size();
        matlab::data::ArrayFactory f;

        // values cell: {curr, input0, ..., inputN-1}
        auto values = f.createCellArray({1, n + 1});
        values[0] = sq::mex::toMda(curr, f);
        for (size_t i = 0; i < n; ++i)
            values[i + 1] = sq::mex::toMda(inputs[i], f);

        // states int8: -1=unset, 0=current/committed, 1=new-working-this-tick
        auto states = f.createArray<int8_t>({1, n + 1});
        states[0] = signals::has_value(curr) ? int8_t(0) : int8_t(-1);
        for (size_t i = 0; i < n; ++i) {
            if (!signals::has_value(inputs[i]))
                states[i + 1] = int8_t(-1);
            else if (signals::has_value(net->get_working_value(ids[i])))
                states[i + 1] = int8_t(1);
            else
                states[i + 1] = int8_t(0);
        }

        try {
            std::vector<matlab::data::Array> args = {fn, values, states};
            auto results = eng->feval(u"feval", 2, args);
            if (results.size() < 2) return {{}, false};
            matlab::data::TypedArray<bool> valset_arr = results[1];
            if (!bool(valset_arr[0])) return {{}, false};
            return {sq::mex::fromMda(results[0]), true};
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

} // namespace sq::mex_ops
