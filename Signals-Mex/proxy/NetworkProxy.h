#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"

#include "mex_network.h"

#include <cstdint>
#include <memory>
#include <unordered_map>

namespace sq::proxy {

/// MEX proxy that owns a signals MexNetwork (NetworkT<matlab::data::Array>).
class NetworkProxy : public libmexclass::proxy::Proxy {
  public:
    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    explicit NetworkProxy(long max_nodes);
    ~NetworkProxy();

    void AddNode(libmexclass::proxy::method::Context& ctx);
    void DeleteNode(libmexclass::proxy::method::Context& ctx);
    void Post(libmexclass::proxy::method::Context& ctx);
    void Transact(libmexclass::proxy::method::Context& ctx);
    void Apply(libmexclass::proxy::method::Context& ctx);
    void GetCurrentValue(libmexclass::proxy::method::Context& ctx);
    void GetWorkingValue(libmexclass::proxy::method::Context& ctx);
    void GetNodeInputs(libmexclass::proxy::method::Context& ctx);
    void SetNodeInputs(libmexclass::proxy::method::Context& ctx);
    void NActiveNodes(libmexclass::proxy::method::Context& ctx);
    void IsValid(libmexclass::proxy::method::Context& ctx);

    // Return a handle (raw pointer value as uint64) that DatostimProxy can use
    // to retrieve the shared MexNetwork from the in-DLL registry.
    void GetNetworkHandle(libmexclass::proxy::method::Context& ctx);

    // Look up a previously registered MexNetwork by handle.
    static std::shared_ptr<MexNetwork> getNetworkByHandle(uintptr_t handle);

  private:
    std::shared_ptr<MexNetwork> net_;

    // Registry lives entirely within signalsproxy.dll — avoids ProxyManager
    // singleton lookup issues that arise with cross-DLL shared state.
    // Stored as a heap pointer so its destructor never runs during abort()
    // cleanup, where the heap may already be in an inconsistent state.
    static std::unordered_map<uintptr_t, std::shared_ptr<MexNetwork>>* s_registry;
};

} // namespace sq::proxy
