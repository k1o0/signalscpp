#include "NetworkProxy.h"
#include "NodeProxy.h"
#include "mx_ops.h"

#include "libmexclass/proxy/ProxyManager.h"
#include "MatlabDataArray.hpp"
#include "value.h"

#include <vector>

namespace sq::proxy {

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

NetworkProxy::NetworkProxy(long max_nodes)
    : net_{std::make_shared<MexNetwork>(max_nodes)}
{
    REGISTER_METHOD(NetworkProxy, AddNode);
    REGISTER_METHOD(NetworkProxy, DeleteNode);
    REGISTER_METHOD(NetworkProxy, Post);
    REGISTER_METHOD(NetworkProxy, Transact);
    REGISTER_METHOD(NetworkProxy, Apply);
    REGISTER_METHOD(NetworkProxy, GetCurrentValue);
    REGISTER_METHOD(NetworkProxy, GetWorkingValue);
    REGISTER_METHOD(NetworkProxy, GetNodeInputs);
    REGISTER_METHOD(NetworkProxy, SetNodeInputs);
    REGISTER_METHOD(NetworkProxy, NActiveNodes);
    REGISTER_METHOD(NetworkProxy, IsValid);
}

libmexclass::proxy::MakeResult NetworkProxy::make(
    const libmexclass::proxy::FunctionArguments& constructor_arguments)
{
    long max_nodes = 4000;
    if (!constructor_arguments.isEmpty()) {
        matlab::data::TypedArray<double> arg =
            static_cast<matlab::data::CellArray>(constructor_arguments)[0];
        max_nodes = static_cast<long>(double(arg[0]));
        if (max_nodes <= 0) {
            return libmexclass::error::Error{
                "sq:invalidArgType", "maxNodes must be a positive integer"};
        }
    }
    return std::make_shared<NetworkProxy>(max_nodes);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

static std::vector<long> extract_ids(const matlab::data::Array& arr) {
    std::vector<long> ids;
    if (arr.isEmpty()) return ids;
    matlab::data::TypedArray<double> ta = arr;
    ids.reserve(arr.getNumberOfElements());
    for (double d : ta) ids.push_back(static_cast<long>(d));
    return ids;
}

// ---------------------------------------------------------------------------
// Method implementations
// ---------------------------------------------------------------------------

void NetworkProxy::AddNode(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 3) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs",
            "AddNode requires (inputIds, opId, appendValues[, fnHandle])"};
        return;
    }

    std::vector<long> input_ids = extract_ids(ctx.inputs[0]);

    matlab::data::TypedArray<double> op_arr = ctx.inputs[1];
    auto op = static_cast<Operation>(static_cast<int>(double(op_arr[0])));

    matlab::data::TypedArray<bool> app_arr = ctx.inputs[2];
    bool append_values = bool(app_arr[0]);

    MexNetwork::NodeCallable callable;
    if (op == Operation::skip_repeats) {
        // Always attach isequal fallback: fast-path for doubles is in C++,
        // this callable is only invoked when values_equal throws TypeError
        // (non-double types) — mirroring the legacy transferInMATLAB pattern.
        callable = sq::mex_ops::wrap_isequal(ctx.matlab);
    } else if (op == Operation::flatten_struct_op) {
        if (!input_ids.empty())
            callable = sq::mex_ops::wrap_flatten_struct_fn(ctx.matlab, net_, input_ids[0]);
    } else if (op == Operation::flatten_op) {
        if (!input_ids.empty())
            callable = sq::mex_ops::wrap_flatten_fn(ctx.matlab, net_, input_ids[0]);
    } else if (ctx.inputs.getNumberOfElements() >= 4) {
        matlab::data::Array fn = ctx.inputs[3];
        if (op == Operation::function)
            callable = sq::mex_ops::wrap_transfer_fn(std::move(fn), ctx.matlab, net_);
        else if (op == Operation::scan_op)
            callable = sq::mex_ops::wrap_matlab_scan_fn(std::move(fn), ctx.matlab);
        else
            callable = sq::mex_ops::wrap_matlab_fn(std::move(fn), ctx.matlab);
    }

    long node_id = net_->add_node(input_ids, op, append_values, std::move(callable));
    if (node_id < 0) {
        ctx.error = libmexclass::error::Error{
            "sq:addNodeFailed", "Failed to add node to network"};
        return;
    }

    auto node_proxy = std::make_shared<sq::proxy::NodeProxy>(net_, node_id);
    libmexclass::proxy::ID proxy_id =
        libmexclass::proxy::ProxyManager::manageProxy(node_proxy);
    matlab::data::ArrayFactory f;
    ctx.outputs[0] = f.createScalar<uint64_t>(proxy_id);
}

void NetworkProxy::DeleteNode(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 1) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "DeleteNode requires (nodeId)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    if (!net_->delete_node(node_id)) {
        ctx.error = libmexclass::error::Error{
            "sq:invalidId", "DeleteNode: invalid or unused node id"};
    }
}

void NetworkProxy::Post(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 2) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "Post requires (nodeId, value)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    try {
        std::vector<long> affected = net_->transact(node_id, ctx.inputs[1]);
        net_->apply(affected);
    } catch (const signals::MatlabError& ex) {
        ctx.error = libmexclass::error::Error{ex.id(), ex.what()};
    } catch (const signals::Error& ex) {
        ctx.error = libmexclass::error::Error{"signals:runtimeError", ex.what()};
    }
}

void NetworkProxy::Transact(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 2) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "Transact requires (nodeId, value)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));

    // Pass the matlab::data::Array directly — no signals::Value conversion.
    std::vector<long> affected;
    try {
        affected = net_->transact(node_id, ctx.inputs[1]);
    } catch (const signals::MatlabError& ex) {
        ctx.error = libmexclass::error::Error{ex.id(), ex.what()};
        return;
    } catch (const signals::Error& ex) {
        ctx.error = libmexclass::error::Error{"signals:runtimeError", ex.what()};
        return;
    }

    matlab::data::ArrayFactory f;
    auto out = f.createArray<double>({1, affected.empty() ? size_t(0) : affected.size()});
    for (size_t i = 0; i < affected.size(); ++i)
        out[i] = static_cast<double>(affected[i]);
    ctx.outputs[0] = out;
}

void NetworkProxy::Apply(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 1) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "Apply requires (affectedIds)"};
        return;
    }
    try {
        net_->apply(extract_ids(ctx.inputs[0]));
    } catch (const signals::MatlabError& ex) {
        ctx.error = libmexclass::error::Error{ex.id(), ex.what()};
    } catch (const signals::Error& ex) {
        ctx.error = libmexclass::error::Error{"signals:runtimeError", ex.what()};
    }
}

void NetworkProxy::GetCurrentValue(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 1) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "GetCurrentValue requires (nodeId)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    // get_current_value returns matlab::data::Array directly — no toMda needed.
    ctx.outputs[0] = net_->get_current_value(node_id);
}

void NetworkProxy::GetWorkingValue(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 1) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "GetWorkingValue requires (nodeId)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    ctx.outputs[0] = net_->get_working_value(node_id);
}

void NetworkProxy::GetNodeInputs(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 1) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "GetNodeInputs requires (nodeId)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    std::vector<long> ids = net_->get_node_inputs(node_id);
    matlab::data::ArrayFactory f;
    auto out = f.createArray<double>({1, ids.empty() ? size_t(0) : ids.size()});
    for (size_t i = 0; i < ids.size(); ++i)
        out[i] = static_cast<double>(ids[i]);
    ctx.outputs[0] = out;
}

void NetworkProxy::SetNodeInputs(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 2) {
        ctx.error = libmexclass::error::Error{
            "sq:notEnoughArgs", "SetNodeInputs requires (nodeId, newInputIds)"};
        return;
    }
    matlab::data::TypedArray<double> id_arr = ctx.inputs[0];
    long node_id = static_cast<long>(double(id_arr[0]));
    std::vector<long> new_ids = extract_ids(ctx.inputs[1]);
    if (!net_->set_node_inputs(node_id, new_ids)) {
        ctx.error = libmexclass::error::Error{
            "sq:invalidId", "SetNodeInputs: invalid node id or input ids"};
    }
}

void NetworkProxy::NActiveNodes(libmexclass::proxy::method::Context& ctx) {
    matlab::data::ArrayFactory f;
    ctx.outputs[0] = f.createScalar<double>(
        static_cast<double>(net_->n_active_nodes()));
}

void NetworkProxy::IsValid(libmexclass::proxy::method::Context& ctx) {
    matlab::data::ArrayFactory f;
    ctx.outputs[0] = f.createScalar<bool>(net_->is_valid());
}

} // namespace sq::proxy
