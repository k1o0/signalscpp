#pragma once
// mx_ops.h — MATLAB boundary wrappers that produce NodeCallable values for use
// with Network::add_node().
//
// Architecture
// ------------
//   Opcode (transferer.h)  — WHICH transfer semantics apply; handled in
//                            Network::Node::transfer().
//   NodeCallable (network.h) — the user's function wrapped for the
//                              Value ↔ mxArray boundary.
//
// Usage
// -----
//   long id = net.add_node({input_id}, Operation::map_op, false,
//                          sq::mex_ops::wrap_matlab_fn(fn, ctx.matlab));
//
//   long id = net.add_node(all_inputs, Operation::scan_op, false,
//                          sq::mex_ops::wrap_matlab_scan_fn(fn, ctx.matlab));

#include "libmexclass/mex/Matlab.h"   // MATLABEngine shared_ptr
#include "MatlabDataArray.hpp"
#include "network.h"
#include "value.h"

#include <memory>
#include <vector>

namespace sq::mex_ops {

using MatlabEngine = std::shared_ptr<matlab::engine::MATLABEngine>;

// ---------------------------------------------------------------------------
// Boundary wrappers — return a NodeCallable to pass directly to add_node()
// ---------------------------------------------------------------------------

/// Wrap a MATLAB function handle for map_op, mapn_op, or filter_op.
/// Invokes:  feval(fn_handle, inputs[0], inputs[1], …)
/// Returns (val, has_value(val)); the current-node-value is NOT forwarded.
Network::NodeCallable wrap_matlab_fn(matlab::data::Array fn_handle, MatlabEngine engine);

/// Wrap a MATLAB function handle for scan_op.
/// Invokes:  feval(fn_handle, accumulator, inputs[0], extra0, …)
/// Returns (val, has_value(val)); accumulator = this node's current value.
Network::NodeCallable wrap_matlab_scan_fn(matlab::data::Array fn_handle, MatlabEngine engine);

/// Wrap a MATLAB @(values, states) closure for function_op (MATLAB transfer mode).
/// Invokes:  [val, valset] = feval(fn_handle, values, states)
/// values — 1×(N+1) cell: {curr, input0, ..., inputN-1} as MATLAB arrays
/// states — 1×(N+1) int8:  -1=unset, 0=current, 1=new-working
/// net and input_ids are used to compute state flags at call time.
Network::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle,
                                       MatlabEngine engine,
                                       std::shared_ptr<Network> net,
                                       std::vector<long> input_ids);

} // namespace sq::mex_ops
