#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"

#include "mex_network.h"

#include <memory>

namespace sq::proxy {

/// MEX proxy that represents a single node inside a MexNetwork.
class NodeProxy : public libmexclass::proxy::Proxy {
  public:
    NodeProxy(std::shared_ptr<MexNetwork> net, long node_id);

    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    void GetId(libmexclass::proxy::method::Context& ctx);
    void GetValue(libmexclass::proxy::method::Context& ctx);
    void GetInputIds(libmexclass::proxy::method::Context& ctx);

  private:
    std::shared_ptr<MexNetwork> net_;
    long id_;
};

} // namespace sq::proxy
