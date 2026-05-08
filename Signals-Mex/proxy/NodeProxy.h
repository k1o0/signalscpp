#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"

#include "network.h"

#include <memory>

namespace sq::proxy {

/// MEX proxy that represents a single node inside a Network.
/// The proxy holds a shared_ptr to the Network so the Network outlives any
/// remaining NodeProxy instances even after sig.Net is garbage-collected.
/// The node's numeric id inside the Network is stored separately.
class NodeProxy : public libmexclass::proxy::Proxy {
  public:
    /// Called by NetworkProxy::AddNode after add_node() succeeds.
    NodeProxy(std::shared_ptr<Network> net, long node_id);

    /// Disallow direct MATLAB construction — NodeProxy instances are only
    /// ever created by NetworkProxy::AddNode.
    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    // -----------------------------------------------------------------------
    // Methods callable from MATLAB via the libmexclass gateway
    // -----------------------------------------------------------------------

    /// GetId() -> double scalar  — the node's id within its Network
    void GetId(libmexclass::proxy::method::Context& ctx);

    /// GetCurrentValue() -> MATLAB array (or [] if never set)
    void GetCurrentValue(libmexclass::proxy::method::Context& ctx);

    /// GetWorkingValue() -> MATLAB array (or [] if not mid-transaction)
    void GetWorkingValue(libmexclass::proxy::method::Context& ctx);

    /// GetInputIds() -> double row vector of upstream node ids
    void GetInputIds(libmexclass::proxy::method::Context& ctx);

  private:
    std::shared_ptr<Network> net_;   ///< shared ownership with NetworkProxy
    long id_;                        ///< node id within net_
};

} // namespace sq::proxy
