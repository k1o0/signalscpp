#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"

#include "network.h"

#include <memory>

namespace sq::proxy {

/// MEX proxy that owns a signals Network.
/// The MATLAB-side sig.Net object references this proxy for its lifetime.
class NetworkProxy : public libmexclass::proxy::Proxy {
  public:
    /// Called by libmexclass when MATLAB constructs a sig.Net object.
    /// constructor_arguments is a cell array; element [0] is maxNodes (double).
    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    explicit NetworkProxy(long max_nodes);

    // -----------------------------------------------------------------------
    // Methods registered with REGISTER_METHOD and callable from MATLAB
    // -----------------------------------------------------------------------

    /// AddNode(inputs_ids, op_id, append_values) -> node_id
    ///   inputs_ids   double row vector (may be empty for source nodes)
    ///   op_id        double scalar (cast to Operation enum)
    ///   append_values logical scalar
    /// Returns: node_id as double scalar, or -1 on failure.
    void AddNode(libmexclass::proxy::method::Context& ctx);

    /// DeleteNode(node_id) -> (none)
    void DeleteNode(libmexclass::proxy::method::Context& ctx);

    /// Transact(node_id, value) -> affected_ids  (double row vector)
    void Transact(libmexclass::proxy::method::Context& ctx);

    /// Apply(affected_ids)  — affected_ids is a double row vector
    void Apply(libmexclass::proxy::method::Context& ctx);

    /// GetCurrentValue(node_id) -> value  (any MATLAB type, or [] if unset)
    void GetCurrentValue(libmexclass::proxy::method::Context& ctx);

    /// GetWorkingValue(node_id) -> value
    void GetWorkingValue(libmexclass::proxy::method::Context& ctx);

    /// GetNodeInputs(node_id) -> double row vector of input node ids
    void GetNodeInputs(libmexclass::proxy::method::Context& ctx);

    /// NActiveNodes() -> double scalar
    void NActiveNodes(libmexclass::proxy::method::Context& ctx);

    /// IsValid() -> logical scalar
    void IsValid(libmexclass::proxy::method::Context& ctx);

  private:
    std::unique_ptr<Network> net_;
};

} // namespace sq::proxy
