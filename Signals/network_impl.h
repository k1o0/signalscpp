#pragma once
// network_impl.h — template method bodies for NetworkT<V>.
//
// Include this file in exactly one translation unit per value type:
//   network.cpp       → template class NetworkT<signals::Value>;
//   mex_network.cpp   → template class NetworkT<matlab::data::Array>;
//
// Every other TU that needs the type should #include "network.h" only,
// and declare: extern template class NetworkT<...>;

#include "network.h"
#include "value_traits.h"

#include <iostream>
#include <queue>
#include <set>
#include <vector>


// ===========================================================================
// NetworkT<V> constructor helpers
// ===========================================================================

template <typename V>
NetworkT<V>::NetworkT(long t_id, long t_max_nodes)
    : id(t_id), max_nodes(t_max_nodes)
{
    nodes.reserve(max_nodes);
}

template <typename V>
void NetworkT<V>::destroy() {
    NetFactory<NetworkT<V>>::destroy(id);
}

template <typename V>
size_t NetworkT<V>::n_active_nodes() {
    size_t count = 0;
    for (const auto& node : nodes)
        if (node.is_valid()) ++count;
    return count;
}

template <typename V>
typename NetworkT<V>::Node* NetworkT<V>::next_free_node() {
    for (size_t i = 0; i < nodes.size(); ++i)
        if (nodes[i].is_available()) return &nodes[i];
    if (nodes.size() < static_cast<size_t>(max_nodes)) {
        nodes.emplace_back(this, static_cast<long>(nodes.size()), Operation::nop);
        return &nodes.back();
    }
    std::cerr << "Error: Maximum number of nodes reached.\n";
    return nullptr;
}

template <typename V>
typename NetworkT<V>::Node* NetworkT<V>::get_node(size_t idx) {
    if (idx >= nodes.size()) {
        std::cerr << "Error: Node index out of range\n";
        return nullptr;
    }
    return &nodes[idx];
}

template <typename V>
long NetworkT<V>::add_node(const std::vector<long>& t_inputs, Operation t_op,
                            bool t_appendValues, NodeCallable callable)
{
    Node* node = next_free_node();
    if (!node) {
        std::cerr << "Error: No free nodes available.\n";
        return -1;
    }
    node->set_transferer(t_op);
    node->appendValues = t_appendValues;
    if (callable)
        node->set_callable(std::move(callable));
    std::vector<Node*> input_nodes;
    for (long input_id : t_inputs) {
        if (input_id < 0 || input_id >= static_cast<long>(n_nodes())) {
            std::cerr << "Error: Input node index " << input_id << " out of range.\n";
            return -1;
        }
        Node* inp = get_node(static_cast<size_t>(input_id));
        if (!inp || !inp->is_valid()) {
            std::cerr << "Error: Input node " << input_id << " invalid.\n";
            return -1;
        }
        input_nodes.push_back(inp);
    }
    node->set_inputs(std::move(input_nodes));
    return node->get_id();
}

template <typename V>
bool NetworkT<V>::set_node_current_value(long node_id, const V& value) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) return false;
    Node& n = nodes[static_cast<size_t>(node_id)];
    if (!n.inUse) return false;
    n.set_current_value(value);
    return true;
}

template <typename V>
bool NetworkT<V>::delete_node(long node_id) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) {
        std::cerr << "Error: delete_node: node ID " << node_id << " out of range.\n";
        return false;
    }
    Node* node = &nodes[static_cast<size_t>(node_id)];
    if (!node->inUse) {
        std::cerr << "Error: delete_node: node " << node_id << " is not active.\n";
        return false;
    }
    for (Node* input : node->inputs)
        input->targets.erase(node);
    for (Node* target : node->targets) {
        auto& inp = target->inputs;
        inp.erase(std::remove(inp.begin(), inp.end(), node), inp.end());
    }
    node->destroy();
    return true;
}

template <typename V>
std::vector<long> NetworkT<V>::transact(long node_id, const V& value) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) {
        std::cerr << "Error: transact: node ID " << node_id << " out of range.\n";
        return {};
    }
    Node* node = &nodes[static_cast<size_t>(node_id)];
    if (!node->is_valid()) {
        std::cerr << "Error: transact: node " << node_id << " is not valid.\n";
        return {};
    }

    // Only post the value if it carries actual content.
    if (!Traits::has_value(value))
        return {};

    node->set_working_value(value);

    std::vector<long> affected;
    std::queue<Node*> todo;
    affected.push_back(node_id);

    for (Node* t : node->targets)
        if (!t->queued) { t->queued = true; todo.push(t); }

    while (!todo.empty()) {
        Node* curr = todo.front(); todo.pop();
        curr->queued = false;
        if (curr->transfer()) {
            affected.push_back(curr->get_id());
            for (Node* t : curr->targets)
                if (!t->queued) { t->queued = true; todo.push(t); }
        }
    }
    return affected;
}

template <typename V>
void NetworkT<V>::apply(const std::vector<long>& affected_ids) {
    using Traits = ValueTraits<V>;
    for (long nid : affected_ids) {
        if (nid < 0 || static_cast<size_t>(nid) >= nodes.size()) continue;
        Node& n = nodes[static_cast<size_t>(nid)];
        if (!n.workingValue) continue;

        if (n.appendValues) {
            V acc = n.currentValue ? *n.currentValue : Traits::no_value();
            n.currentValue = Traits::append(acc, *n.workingValue);
        } else {
            n.currentValue = std::move(n.workingValue);
        }
        n.workingValue = std::nullopt;
    }
}

template <typename V>
V NetworkT<V>::get_current_value(long node_id) const {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size())
        return Traits::no_value();
    const Node& n = nodes[static_cast<size_t>(node_id)];
    return n.currentValue.value_or(Traits::no_value());
}

template <typename V>
V NetworkT<V>::get_working_value(long node_id) const {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size())
        return Traits::no_value();
    const Node& n = nodes[static_cast<size_t>(node_id)];
    return n.workingValue.value_or(Traits::no_value());
}

template <typename V>
V NetworkT<V>::get_latest_value(long node_id) const {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size())
        return Traits::no_value();
    const Node& n = nodes[static_cast<size_t>(node_id)];
    if (n.workingValue) return *n.workingValue;
    return n.currentValue.value_or(Traits::no_value());
}

template <typename V>
bool NetworkT<V>::clear_working_value(long node_id) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) return false;
    Node& n = nodes[static_cast<size_t>(node_id)];
    if (!n.inUse) return false;
    n.workingValue = std::nullopt;
    return true;
}

template <typename V>
std::vector<long> NetworkT<V>::get_node_inputs(long node_id) const {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) return {};
    const Node& n = nodes[static_cast<size_t>(node_id)];
    if (!n.inUse) return {};
    std::vector<long> ids;
    ids.reserve(n.inputs.size());
    for (const Node* inp : n.inputs) ids.push_back(inp->id);
    return ids;
}

template <typename V>
bool NetworkT<V>::set_node_inputs(long node_id, const std::vector<long>& new_input_ids) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) return false;
    Node* node = &nodes[static_cast<size_t>(node_id)];
    if (!node->inUse) return false;

    // Remove this node from all current inputs' target sets.
    for (Node* inp : node->inputs)
        inp->targets.erase(node);

    // Build the new input list.
    std::vector<Node*> new_inputs;
    new_inputs.reserve(new_input_ids.size());
    for (long input_id : new_input_ids) {
        if (input_id < 0 || input_id >= static_cast<long>(n_nodes())) {
            std::cerr << "Error: set_node_inputs: input node " << input_id << " out of range.\n";
            return false;
        }
        Node* inp = get_node(static_cast<size_t>(input_id));
        if (!inp || !inp->is_valid()) {
            std::cerr << "Error: set_node_inputs: input node " << input_id << " invalid.\n";
            return false;
        }
        new_inputs.push_back(inp);
    }

    node->inputs = std::move(new_inputs);

    // Register this node as a target of each new input.
    for (Node* inp : node->inputs)
        inp->add_target(node);

    return true;
}


// ===========================================================================
// NetworkT<V>::Node methods
// ===========================================================================

template <typename V>
NetworkT<V>::Node::Node(NetworkT* t_net, long t_id, Operation t_op)
    : net(t_net), id(t_id), transferer(t_op)
{
    if (!t_net || !t_net->is_valid()) {
        std::cerr << "Error: Network is not valid.\n";
        net = nullptr;
    }
}

template <typename V>
void NetworkT<V>::Node::destroy() {
    inUse = false;
    queued = false;
    workingValue = std::nullopt;
    currentValue = std::nullopt;
    inputs.clear();
    targets.clear();
    transferer.set_callable({});
}

template <typename V>
long NetworkT<V>::Node::get_id() const {
    if (!net || !net->is_valid()) {
        std::cerr << "Error: Network is not valid.\n";
        return -1;
    }
    if (id < 0 || id > static_cast<long>(net->n_nodes())) {
        std::cerr << "Error: Node ID is out of range.\n";
        return -1;
    }
    return id;
}

template <typename V>
void NetworkT<V>::Node::set_working_value(const V& value) {
    if (Traits::has_value(value))
        workingValue = value;
    else
        workingValue = std::nullopt;
}

template <typename V>
void NetworkT<V>::Node::set_current_value(const V& value) {
    if (Traits::has_value(value))
        currentValue = value;
    else
        currentValue = std::nullopt;
}

template <typename V>
void NetworkT<V>::Node::set_inputs(std::vector<NetworkT::Node*> t_inputs) {
    inputs = std::move(t_inputs);
    inUse = true;
    for (Node* inp : inputs) {
        if (!inp->is_valid()) {
            std::cerr << "Error: Input node is not valid.\n";
            continue;
        }
        inp->add_target(this);
    }
}

// ---------------------------------------------------------------------------
// NetworkT<V>::Node::transfer()
//
// Recompute this node's working value from its inputs and return true when
// propagation to targets should continue.
//
// Uses ValueTraits<V> (aliased as Traits) for all type-specific operations:
//   has_value, is_truthy, values_equal, from_bool, from_double,
//   numel, to_index, add/subtract/… (throw TypeError by default — option ii)
// ---------------------------------------------------------------------------
template <typename V>
bool NetworkT<V>::Node::transfer() {
    using Traits = ValueTraits<V>;
    const int op_int = static_cast<int>(transferer.get_op());
    const Operation op = transferer.get_op();
    const typename TransfererT<V>::NodeCallable& callable = transferer.get_callable();

    // Prefer working value; fall back to current value.  Returns nullopt if neither set.
    auto latest = [](const Node* n) -> std::optional<V> {
        if (n->workingValue) return n->workingValue;
        return n->currentValue;
    };

    bool produced_output = false;

    // ── Binary arithmetic and comparison ops (opcodes 1-14) ──────────────────
    if (op_int >= 1 && op_int <= 14) {
        if (inputs.size() >= 2 &&
            (inputs[0]->workingValue.has_value() || inputs[1]->workingValue.has_value()))
        {
            auto lv_opt = latest(inputs[0]);
            auto rv_opt = latest(inputs[1]);
            if (lv_opt && rv_opt) {
                try {
                    V result;
                    switch (op) {
                        case Operation::plus:    result = Traits::add(*lv_opt, *rv_opt);      break;
                        case Operation::minus:   result = Traits::subtract(*lv_opt, *rv_opt); break;
                        case Operation::mtimes:  result = Traits::multiply(*lv_opt, *rv_opt); break;
                        case Operation::rdivide: result = Traits::rdivide(*lv_opt, *rv_opt);  break;
                        case Operation::mdivide: result = Traits::ldivide(*lv_opt, *rv_opt);  break;
                        case Operation::gt:      result = Traits::gt(*lv_opt, *rv_opt);       break;
                        case Operation::ge:      result = Traits::ge(*lv_opt, *rv_opt);       break;
                        case Operation::lt:      result = Traits::lt(*lv_opt, *rv_opt);       break;
                        case Operation::le:      result = Traits::le(*lv_opt, *rv_opt);       break;
                        case Operation::eq:      result = Traits::eq(*lv_opt, *rv_opt);       break;
                        default: break;
                    }
                    if (Traits::has_value(result)) {
                        workingValue = std::move(result);
                        produced_output = true;
                    }
                } catch (const signals::TypeError&) {
                    // Type doesn't support native arithmetic — fall back to callable (option ii).
                    if (callable) {
                        try {
                            V curr = currentValue.value_or(Traits::no_value());
                            auto [res, valset] = callable({*lv_opt, *rv_opt}, curr, id);
                            if (valset) { workingValue = std::move(res); produced_output = true; }
                        } catch (const signals::Error&) { throw; }
                          catch (...) {}
                    }
                }
            }
        }
    }

    // ── identity (50) ────────────────────────────────────────────────────────
    else if (op == Operation::identity) {
        if (!inputs.empty() && inputs[0]->workingValue) {
            workingValue = inputs[0]->workingValue;
            produced_output = true;
        }
    }

    // ── merge (20) ───────────────────────────────────────────────────────────
    else if (op == Operation::merge) {
        for (Node* inp : inputs) {
            if (inp->workingValue) {
                workingValue = inp->workingValue;
                produced_output = true;
                break;
            }
        }
    }

    // ── at_op (21) ───────────────────────────────────────────────────────────
    // fires latest 'what' when 'when' has a new truthy working value
    else if (op == Operation::at_op) {
        if (inputs.size() >= 2 && inputs[1]->workingValue &&
            Traits::is_truthy(*inputs[1]->workingValue))
        {
            auto what_opt = latest(inputs[0]);
            if (what_opt) { workingValue = *what_opt; produced_output = true; }
        }
    }

    // ── keep_when (22) ───────────────────────────────────────────────────────
    // fires 'what' working value when 'when' latest is truthy
    else if (op == Operation::keep_when) {
        if (inputs.size() >= 2 && inputs[0]->workingValue) {
            auto when_opt = latest(inputs[1]);
            if (when_opt && Traits::is_truthy(*when_opt)) {
                workingValue = inputs[0]->workingValue;
                produced_output = true;
            }
        }
    }

    // ── latch (23) ───────────────────────────────────────────────────────────
    else if (op == Operation::latch) {
        if (inputs.size() >= 2) {
            const bool arm_new     = inputs[0]->workingValue.has_value();
            const bool release_new = inputs[1]->workingValue.has_value();
            const bool try_arm     = arm_new     && Traits::is_truthy(*inputs[0]->workingValue);
            const bool try_release = release_new && Traits::is_truthy(*inputs[1]->workingValue);
            const bool armed = currentValue && Traits::is_truthy(*currentValue);
            if (try_release && (try_arm || armed)) {
                workingValue = Traits::from_bool(false);
                produced_output = true;
            } else if (!armed && try_arm) {
                workingValue = Traits::from_bool(true);
                produced_output = true;
            }
        }
    }

    // ── skip_repeats (24) ────────────────────────────────────────────────────
    // Fast path: C++ values_equal for scalar doubles.
    // Fallback: callable (e.g. wrap_isequal) for types that throw TypeError —
    // mirrors legacy mexnet: double-scalar C path, transferInMATLAB otherwise.
    else if (op == Operation::skip_repeats) {
        if (!inputs.empty() && inputs[0]->workingValue) {
            const V& wv = *inputs[0]->workingValue;
            bool should_fire = false;
            if (!currentValue) {
                should_fire = true;
            } else {
                try {
                    should_fire = !Traits::values_equal(wv, *currentValue);
                } catch (const signals::TypeError&) {
                    if (callable) {
                        // callable({wv, cv}, cv, id) returns (is_equal, valset);
                        // is_equal truthy → values match → suppress output.
                        try {
                            auto [eq_result, valset] =
                                callable({wv, *currentValue}, *currentValue, id);
                            should_fire = !valset || !Traits::is_truthy(eq_result);
                        } catch (const signals::Error&) { throw; }
                          catch (...) { should_fire = true; }
                    } else {
                        should_fire = true;  // conservative: always propagate
                    }
                }
            }
            if (should_fire) {
                workingValue = wv;
                produced_output = true;
            }
        }
    }

    // ── select_from (25) ─────────────────────────────────────────────────────
    else if (op == Operation::select_from) {
        if (inputs.size() >= 2) {
            auto idx_opt = latest(inputs[0]);
            if (idx_opt) {
                auto idx_sz = Traits::to_index(*idx_opt);
                const size_t n_options = inputs.size() - 1;
                if (idx_sz && *idx_sz < n_options) {
                    Node* selected = inputs[*idx_sz + 1];
                    const bool index_changed  = inputs[0]->workingValue.has_value();
                    const bool option_changed = selected->workingValue.has_value();
                    if (index_changed || option_changed) {
                        auto sel_opt = latest(selected);
                        if (sel_opt) { workingValue = *sel_opt; produced_output = true; }
                    }
                }
            }
        }
    }

    // ── index_of_first (26) ──────────────────────────────────────────────────
    else if (op == Operation::index_of_first) {
        bool any_new = false;
        for (Node* inp : inputs)
            if (inp->workingValue) { any_new = true; break; }
        if (any_new) {
            for (size_t i = 0; i < inputs.size(); ++i) {
                auto v = latest(inputs[i]);
                if (v && Traits::is_truthy(*v)) {
                    workingValue = Traits::from_double(static_cast<double>(i));
                    produced_output = true;
                    break;
                }
            }
        }
    }

    // ── function (0): MATLAB transfer callable ────────────────────────────────
    // Invoked when any input fired.  Callable handles all gating internally.
    else if (op == Operation::function) {
        if (callable) {
            // Check that at least one input fired.
            bool any_new = false;
            for (Node* inp : inputs)
                if (inp->workingValue) { any_new = true; break; }
            if (any_new) {
                std::vector<V> inp_latest;
                inp_latest.reserve(inputs.size());
                for (Node* inp : inputs) {
                    auto v = latest(inp);
                    inp_latest.push_back(v ? *v : Traits::no_value());
                }
                V curr = currentValue.value_or(Traits::no_value());
                try {
                    auto [result, valset] = callable(inp_latest, curr, id);
                    if (valset) {
                        workingValue = std::move(result);
                        produced_output = true;
                    } else if (workingValue) {
                        workingValue = std::nullopt;
                        produced_output = true;
                    }
                } catch (const signals::Error&) { throw; }
                  catch (...) {}
            }
        }
    }

    // ── numel (30) ────────────────────────────────────────────────────────────
    else if (op == Operation::numel) {
        if (!inputs.empty() && inputs[0]->workingValue) {
            workingValue = Traits::from_double(Traits::numel(*inputs[0]->workingValue));
            produced_output = true;
        }
    }

    // ── map_op (60) ───────────────────────────────────────────────────────────
    else if (op == Operation::map_op) {
        if (!inputs.empty() && inputs[0]->workingValue) {
            if (callable) {
                // map(fn): apply fn to inputs[0]
                auto lv = latest(inputs[0]);
                V curr = currentValue.value_or(Traits::no_value());
                try {
                    auto [result, valset] = callable({lv ? *lv : Traits::no_value()}, curr, id);
                    if (valset) { workingValue = std::move(result); produced_output = true; }
                } catch (const signals::Error&) { throw; }
                  catch (...) {}
            } else if (inputs.size() >= 2) {
                // map(signal/constant): sample inputs[1] when inputs[0] fires
                auto fv = latest(inputs[1]);
                if (fv) { workingValue = *fv; produced_output = true; }
            }
        }
    }

    // ── mapn_op (61) ──────────────────────────────────────────────────────────
    else if (op == Operation::mapn_op) {
        if (!inputs.empty() && callable) {
            bool any_new = false;
            for (Node* inp : inputs)
                if (inp->workingValue) { any_new = true; break; }
            if (any_new) {
                std::vector<V> vals;
                vals.reserve(inputs.size());
                bool all_available = true;
                for (Node* inp : inputs) {
                    auto v = latest(inp);
                    if (!v) { all_available = false; break; }
                    vals.push_back(*v);
                }
                if (all_available) {
                    V curr = currentValue.value_or(Traits::no_value());
                    try {
                        auto [result, valset] = callable(vals, curr, id);
                        if (valset) { workingValue = std::move(result); produced_output = true; }
                    } catch (const signals::Error&) { throw; }
                      catch (...) {}
                }
            }
        }
    }

    // ── filter_op (62) ────────────────────────────────────────────────────────
    else if (op == Operation::filter_op) {
        if (!inputs.empty() && callable && inputs[0]->workingValue) {
            V curr = currentValue.value_or(Traits::no_value());
            try {
                auto [indicator, valset] =
                    callable({*inputs[0]->workingValue}, curr, id);
                if (valset && Traits::is_truthy(indicator)) {
                    workingValue = inputs[0]->workingValue;
                    produced_output = true;
                }
            } catch (const signals::Error&) { throw; }
              catch (...) {}
        }
    }

    // ── scan_op (63) ──────────────────────────────────────────────────────────
    else if (op == Operation::scan_op) {
        if (inputs.size() >= 2 && callable) {
            const bool item_new = inputs[0]->workingValue.has_value();
            const bool seed_new = inputs[1]->workingValue.has_value();
            bool extra_new = false;
            for (size_t i = 2; i < inputs.size(); ++i)
                if (inputs[i]->workingValue) { extra_new = true; break; }

            if (seed_new && !item_new && !extra_new) {
                workingValue = inputs[1]->workingValue;
                produced_output = true;
            } else if (item_new || extra_new) {
                // Accumulator: seed this tick > committed current > seed's latest
                std::optional<V> acc_opt;
                if (seed_new)
                    acc_opt = inputs[1]->workingValue;
                else if (currentValue)
                    acc_opt = currentValue;
                else
                    acc_opt = latest(inputs[1]);

                auto item_opt = latest(inputs[0]);
                if (acc_opt && item_opt) {
                    std::vector<V> call_inputs;
                    call_inputs.push_back(*item_opt);
                    for (size_t i = 2; i < inputs.size(); ++i) {
                        auto v = latest(inputs[i]);
                        call_inputs.push_back(v ? *v : Traits::no_value());
                    }
                    try {
                        auto [result, valset] = callable(call_inputs, *acc_opt, id);
                        if (valset) { workingValue = std::move(result); produced_output = true; }
                    } catch (const signals::Error&) { throw; }
                      catch (...) {}
                }
            }
        }
    }
    // ── flatten_struct_op (40) ────────────────────────────────────────────────
    // callable handles all gating: rewires on blueprint fire, checks field values,
    // and assembles the output struct.  Same invocation pattern as function_op.
    else if (op == Operation::flatten_struct_op) {
        if (callable) {
            bool any_new = false;
            for (Node* inp : inputs)
                if (inp->workingValue) { any_new = true; break; }
            if (any_new) {
                std::vector<V> inp_latest;
                inp_latest.reserve(inputs.size());
                for (Node* inp : inputs) {
                    auto v = latest(inp);
                    inp_latest.push_back(v ? *v : Traits::no_value());
                }
                V curr = currentValue.value_or(Traits::no_value());
                try {
                    auto [result, valset] = callable(inp_latest, curr, id);
                    if (valset) {
                        workingValue = std::move(result);
                        produced_output = true;
                    } else if (workingValue) {
                        workingValue = std::nullopt;
                        produced_output = true;
                    }
                } catch (const signals::Error&) { throw; }
                  catch (...) {}
            }
        }
    }

    // ── flatten_op (41) ───────────────────────────────────────────────────────
    // inputs[0] = director.  When director fires, callable may rewire inputs[1]
    // to a new source node and return that source's latest value (or return the
    // plain value directly when director holds a non-Signal).
    // inputs[1] = source (after first rewire): pure C++ passthrough, no feval.
    else if (op == Operation::flatten_op) {
        if (!inputs.empty() && inputs[0]->workingValue) {
            if (callable) {
                V curr = currentValue.value_or(Traits::no_value());
                try {
                    auto [result, valset] = callable({*inputs[0]->workingValue}, curr, id);
                    if (valset) { workingValue = std::move(result); produced_output = true; }
                } catch (const signals::Error&) { throw; }
                  catch (...) {}
            }
        } else if (inputs.size() >= 2 && inputs[1]->workingValue) {
            workingValue = inputs[1]->workingValue;
            produced_output = true;
        }
    }

    // nop (51): source node — transfer() is never meaningfully called.

    if (produced_output) return true;

    // No new output this tick.  If a working value was previously set, clear it
    // and return true so downstream nodes can react to the unset.
    if (workingValue) {
        workingValue = std::nullopt;
        return true;
    }
    return false;
}
