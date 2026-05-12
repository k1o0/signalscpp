#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"
#include "libmexclass/proxy/ProxyManager.h"

#include "mex_network.h"

#include <memory>

namespace sq::proxy {

/// MEX proxy that owns a signals MexNetwork (NetworkT<matlab::data::Array>).
class NetworkProxy : public libmexclass::proxy::Proxy {
  public:
    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    explicit NetworkProxy(long max_nodes);

    void AddNode(libmexclass::proxy::method::Context& ctx);
    void DeleteNode(libmexclass::proxy::method::Context& ctx);
    void Post(libmexclass::proxy::method::Context& ctx);
    void Transact(libmexclass::proxy::method::Context& ctx);
    void Apply(libmexclass::proxy::method::Context& ctx);
    void GetCurrentValue(libmexclass::proxy::method::Context& ctx);
    void GetWorkingValue(libmexclass::proxy::method::Context& ctx);
    void GetNodeInputs(libmexclass::proxy::method::Context& ctx);
    void NActiveNodes(libmexclass::proxy::method::Context& ctx);
    void IsValid(libmexclass::proxy::method::Context& ctx);

  private:
    std::shared_ptr<MexNetwork> net_;
};

} // namespace sq::proxy
