#include "NodeProxy.h"
#include "MatlabDataArray.hpp"

namespace sq::proxy {

NodeProxy::NodeProxy(std::shared_ptr<MexNetwork> net, long node_id)
    : net_{std::move(net)}, id_{node_id}
{
    REGISTER_METHOD(NodeProxy, GetId);
    REGISTER_METHOD(NodeProxy, GetValue);
    REGISTER_METHOD(NodeProxy, GetInputIds);
}

libmexclass::proxy::MakeResult NodeProxy::make(
    const libmexclass::proxy::FunctionArguments& /*constructor_arguments*/)
{
    return libmexclass::error::Error{
        "sq:signals:nodeDirectCreate",
        "sig.Node cannot be created directly; use sig.Net.addNode()"};
}

void NodeProxy::GetId(libmexclass::proxy::method::Context& ctx) {
    matlab::data::ArrayFactory f;
    ctx.outputs[0] = f.createScalar<double>(static_cast<double>(id_));
}

void NodeProxy::GetValue(libmexclass::proxy::method::Context& ctx) {
    // get_latest_value returns matlab::data::Array directly — no toMda needed.
    ctx.outputs[0] = net_->get_latest_value(id_);
}

void NodeProxy::GetInputIds(libmexclass::proxy::method::Context& ctx) {
    std::vector<long> ids = net_->get_node_inputs(id_);
    matlab::data::ArrayFactory f;
    auto out = f.createArray<double>({1, ids.empty() ? size_t(0) : ids.size()});
    for (size_t i = 0; i < ids.size(); ++i)
        out[i] = static_cast<double>(ids[i]);
    ctx.outputs[0] = out;
}

} // namespace sq::proxy
