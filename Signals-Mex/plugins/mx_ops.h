#pragma once
// mx_ops.h — MATLAB boundary wrappers that produce MexNetwork::NodeCallable values.
//
// Architecture
// ------------
//   Opcode (transferer.h)    — WHICH transfer semantics apply; handled in
//                              NetworkT<V>::Node::transfer().
//   NodeCallable (mex_network.h) — the user's function wrapped for the
//                              matlab::data::Array ↔ MATLAB feval boundary.
//
// Usage
// -----
//   long id = net.add_node({input_id}, Operation::map_op, false,
//                          sq::mex_ops::wrap_matlab_fn(fn, ctx.matlab));
//
//   long id = net.add_node(all_inputs, Operation::scan_op, false,
//                          sq::mex_ops::wrap_matlab_scan_fn(fn, ctx.matlab));

#include "libmexclass/mex/Matlab.h"
#include "MatlabDataArray.hpp"
#include "mex_network.h"

#include <memory>
#include <vector>

namespace sq::mex_ops {

using MatlabEngine = std::shared_ptr<matlab::engine::MATLABEngine>;

// ---------------------------------------------------------------------------
// Boundary wrappers — return a MexNetwork::NodeCallable for add_node()
// ---------------------------------------------------------------------------

/// Wrap a MATLAB function handle for map_op, mapn_op, or filter_op.
/// Invokes:  result = feval(fn_handle, input0, input1, …)
/// matlab::data::Array values are forwarded directly — no conversion.
MexNetwork::NodeCallable wrap_matlab_fn(matlab::data::Array fn_handle,
                                        MatlabEngine engine);

/// Wrap a MATLAB function handle for scan_op.
/// Invokes:  result = feval(fn_handle, accumulator, item, extra0, …)
MexNetwork::NodeCallable wrap_matlab_scan_fn(matlab::data::Array fn_handle,
                                             MatlabEngine engine);

/// Wrap a MATLAB isequal() call for skip_repeats equality fallback.
/// Invokes:  result = isequal(inputs[0], inputs[1])
/// Returns (is_equal_logical, true); truthy result means values are equal → suppress.
/// Attached automatically by NetworkProxy::AddNode for skip_repeats nodes.
MexNetwork::NodeCallable wrap_isequal(MatlabEngine engine);

/// Wrap a MATLAB @(values, states) closure for function_op (MATLAB transfer mode).
/// Invokes:  [val, valset] = feval(fn_handle, values, states)
/// values — 1×(N+1) cell: {curr, input0, ..., inputN-1}
/// states — 1×(N+1) int8:  -1=unset, 0=current, 1=new-working
/// Input IDs are queried dynamically at call time (correct after rewiring).
MexNetwork::NodeCallable wrap_transfer_fn(matlab::data::Array fn_handle,
                                          MatlabEngine engine,
                                          std::shared_ptr<MexNetwork> net);

/// Callable for flatten_op (41).
/// When director (inputs[0]) fires with a sig.Signal value, rewires inputs[1] to
/// that signal's node and returns the source's latest value (if any).
/// When director fires with a plain value, outputs it directly (no subscription).
/// director_id is the node ID of inputs[0], captured at construction.
MexNetwork::NodeCallable wrap_flatten_fn(MatlabEngine engine,
                                         std::shared_ptr<MexNetwork> net,
                                         long director_id);

/// Callable for flatten_struct_op (40).
/// When blueprint (inputs[0]) fires, calls sig.Node.flattenInfo to get signal-field
/// metadata, rewires this node's inputs, and outputs the struct if all fields have
/// values.  On subsequent field-signal fires, assembles the struct via
/// sig.Node.fillStructFields.  blueprint_id is the node ID of inputs[0].
MexNetwork::NodeCallable wrap_flatten_struct_fn(MatlabEngine engine,
                                                std::shared_ptr<MexNetwork> net,
                                                long blueprint_id);

} // namespace sq::mex_ops
