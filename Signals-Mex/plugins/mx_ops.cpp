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
        } catch (const matlab::engine::MATLABException& ex) {
            throw signals::MatlabError(ex.getMessageID(), ex.what());
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
        } catch (const matlab::engine::MATLABException& ex) {
            throw signals::MatlabError(ex.getMessageID(), ex.what());
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

MexNetwork::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle,
                                          MatlabEngine engine,
                                          std::shared_ptr<MexNetwork> net)
{
    // fn_handle is a closure @(values, states) sig.transfer.xxx(values, states, f)
    // Builds values cell {curr, input0, ..., inputN-1} and states int8 vector,
    // then invokes: [val, valset] = feval(fn_handle, values, states)
    //
    // Input IDs are fetched dynamically via get_node_inputs so this callable
    // remains correct after any set_node_inputs rewiring.
    //
    // states encoding:
    //   -1 = no value at all (never fired and not fired this tick)
    //    0 = current/committed value only (not fired this tick)
    //    1 = new working value this tick
    return [fn  = std::move(fn_handle),
            eng = std::move(engine),
            net = std::move(net)]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& curr,
            long node_id) -> std::pair<matlab::data::Array, bool>
    {
        const size_t n = inputs.size();
        matlab::data::ArrayFactory f;

        // Resolve current input IDs dynamically.
        auto current_ids = net->get_node_inputs(node_id);

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
            } else if (i < current_ids.size() &&
                       Traits::has_value(net->get_working_value(current_ids[i]))) {
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
        } catch (const matlab::engine::MATLABException& ex) {
            throw signals::MatlabError(ex.getMessageID(), ex.what());
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError: ") + e.what());
        }
    };
}

// ---------------------------------------------------------------------------
// Flatten wrappers
// ---------------------------------------------------------------------------

MexNetwork::NodeCallable wrap_flatten_fn(MatlabEngine engine,
                                          std::shared_ptr<MexNetwork> net,
                                          long director_id)
{
    // Called when director (inputs[0]) fires.
    // Calls sig.Node.idOf on the director value to test whether it is a Signal:
    //   >= 0  → Signal: rewire inputs[1] to that source node, return source's
    //            latest value (or empty if the source has never fired).
    //   < 0   → plain value: output directly, remove source subscription.
    return [eng = std::move(engine),
            net = std::move(net),
            director_id]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& /*curr*/,
            long node_id) -> std::pair<matlab::data::Array, bool>
    {
        if (inputs.empty()) return {make_empty(), false};

        using Traits = ValueTraits<matlab::data::Array>;

        try {
            std::vector<matlab::data::Array> id_args = {inputs[0]};
            auto id_results = eng->feval(u"sig.Node.idOf", 1, id_args);
            if (id_results.empty()) return {make_empty(), false};

            matlab::data::TypedArray<double> id_arr = id_results[0];
            long source_id = static_cast<long>(double(id_arr[0]));

            if (source_id >= 0) {
                // Director holds a Signal — rewire inputs[1] to its node.
                net->set_node_inputs(node_id, {director_id, source_id});
                auto src_val = net->get_latest_value(source_id);
                if (Traits::has_value(src_val)) return {src_val, true};
                return {make_empty(), false};
            } else {
                // Director holds a plain value — output it and drop any source.
                net->set_node_inputs(node_id, {director_id});
                return {inputs[0], true};
            }
        } catch (const matlab::engine::MATLABException& ex) {
            throw signals::MatlabError(ex.getMessageID(), ex.what());
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError:flatten: ") + e.what());
        }
    };
}

namespace {
struct FlatStructState {
    matlab::data::Array field_names_cell;
    matlab::data::Array tmpl;
    bool initialized = false;
};
} // anonymous namespace

MexNetwork::NodeCallable wrap_flatten_struct_fn(MatlabEngine engine,
                                                std::shared_ptr<MexNetwork> net,
                                                long blueprint_id)
{
    auto state = std::make_shared<FlatStructState>();

    return [eng = std::move(engine),
            net = std::move(net),
            blueprint_id,
            state]
           (const std::vector<matlab::data::Array>& inputs,
            const matlab::data::Array& /*curr*/,
            long node_id) -> std::pair<matlab::data::Array, bool>
    {
        using Traits = ValueTraits<matlab::data::Array>;

        bool blueprint_fired = Traits::has_value(net->get_working_value(blueprint_id));

        if (blueprint_fired && !inputs.empty() && Traits::has_value(inputs[0])) {
            // Blueprint fired: extract signal-field info and rewire.
            try {
                std::vector<matlab::data::Array> info_args = {inputs[0]};
                auto info = eng->feval(u"sig.Node.flattenInfo", 3, info_args);
                if (info.size() >= 3) {
                    state->field_names_cell = info[0];  // 1×N cell of char
                    state->tmpl             = info[2];  // template struct
                    state->initialized      = true;

                    matlab::data::TypedArray<double> nids = info[1];
                    std::vector<long> new_inputs = {blueprint_id};
                    for (double d : nids) new_inputs.push_back(static_cast<long>(d));
                    net->set_node_inputs(node_id, new_inputs);
                }
            } catch (const matlab::engine::MATLABException& ex) {
                throw signals::MatlabError(ex.getMessageID(), ex.what());
            } catch (const std::exception& e) {
                throw signals::Error(std::string("sq:fevalError:flattenInfo: ") + e.what());
            }
        }

        if (!state->initialized) return {make_empty(), false};

        // Get current input list (after possible rewire above).
        auto cur_inputs = net->get_node_inputs(node_id);
        size_t n_fields = cur_inputs.size() > 1 ? cur_inputs.size() - 1 : 0;

        if (n_fields == 0) {
            // No signal fields — output the template as-is when blueprint fires.
            if (blueprint_fired && Traits::has_value(state->tmpl))
                return {state->tmpl, true};
            return {make_empty(), false};
        }

        // Gate: all field inputs must have at least a committed value.
        // This fixes the old C bug where the struct was output even when some
        // field signals had never fired.
        bool all_have_value = true;
        bool any_field_new  = false;
        for (size_t i = 1; i < cur_inputs.size(); ++i) {
            auto lv = net->get_latest_value(cur_inputs[i]);
            if (!Traits::has_value(lv)) { all_have_value = false; break; }
            if (Traits::has_value(net->get_working_value(cur_inputs[i])))
                any_field_new = true;
        }

        if (!all_have_value)              return {make_empty(), false};
        if (!blueprint_fired && !any_field_new) return {make_empty(), false};

        // Assemble the output struct via sig.Node.fillStructFields.
        try {
            std::vector<matlab::data::Array> fill_args;
            fill_args.push_back(state->tmpl);
            fill_args.push_back(state->field_names_cell);
            for (size_t i = 1; i < cur_inputs.size(); ++i)
                fill_args.push_back(net->get_latest_value(cur_inputs[i]));

            auto res = eng->feval(u"sig.Node.fillStructFields", 1, fill_args);
            if (res.empty()) return {make_empty(), false};
            return {res[0], true};
        } catch (const matlab::engine::MATLABException& ex) {
            throw signals::MatlabError(ex.getMessageID(), ex.what());
        } catch (const std::exception& e) {
            throw signals::Error(std::string("sq:fevalError:fillStructFields: ") + e.what());
        }
    };
}

} // namespace sq::mex_ops
