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

Network::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle, MatlabEngine engine)
{
    // fn_handle is a closure @(node) sig.transfer.xxx(net, inputIds, node, customArg)
    // Invoked as: [val, valset] = feval(fn_handle, node_id)
    // The closure handles all input gating and returns an explicit valset flag.
    return [fn = std::move(fn_handle), eng = std::move(engine)]
           (const std::vector<signals::Value>& /*inputs*/,
            const signals::Value& /*curr*/,
            long node_id) -> std::pair<signals::Value, bool>
    {
        matlab::data::ArrayFactory f;
        std::vector<matlab::data::Array> args = {
            fn, f.createScalar<double>(static_cast<double>(node_id))
        };
        try {
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
