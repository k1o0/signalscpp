#pragma once
#ifndef __NETWORK_H_INCLUDED__
#define __NETWORK_H_INCLUDED__

#if defined(SIGNALS_STATIC_LIB)
#define SIGNALS_API
#elif defined(SIGNALS_EXPORTS)
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

#include "transferer.h"
#include "value_traits.h"
#include <algorithm>
#include <functional>
#include <memory>
#include <optional>
#include <set>
#include <vector>

constexpr int CORE_LIB_VERSION_MAJOR = 0;
constexpr int CORE_LIB_VERSION_MINOR = 1;
constexpr int CORE_LIB_VERSION_PATCH = 0;

// https://stackoverflow.com/a/28055997
template <typename T>
class NetFactory {
private:
    inline static std::vector<std::unique_ptr<T>> networks = {};

public:
    static const int MAX_NETWORKS{ 10 };
    static T* create() {
        if (networks.size() >= MAX_NETWORKS)
            throw std::runtime_error("Maximum number of networks reached");
        std::unique_ptr<T> obj{ new T(networks.size(), long(4000)) };
        obj->id = networks.size();
        obj->active = true;
        networks.emplace_back(std::move(obj));
        return networks.back().get();
    }

    static void destroy(long id) {
        if (id < 0 || id >= static_cast<long>(networks.size()))
            throw std::out_of_range("Network index out of range");
        size_t idx = static_cast<size_t>(id);
        if (!networks[idx])
            throw std::runtime_error("Network already destroyed or invalid");
        networks[idx]->active = false;
        for (auto& node : networks[idx]->nodes)
            node.destroy();
        networks[idx]->nodes.clear();
        networks[idx].reset();
    }

    static size_t destroy_all() {
        size_t n_destroyed = 0;
        for (auto& net : networks) {
            if (net) {
                n_destroyed++;
                NetFactory<T>::destroy(net->get_id());
            }
        }
        networks.clear();
        return n_destroyed;
    }

    static bool is_valid(T* net) {
        return std::any_of(networks.begin(), networks.end(),
            [net](const std::unique_ptr<T>& ptr) { return ptr.get() == net; });
    }
};


// ---------------------------------------------------------------------------
// NetworkT<V> — reactive signal network templated on the value type V.
//
// V is the native value type for this binding:
//   signals::Value        — standalone / unit-test build
//   matlab::data::Array   — MEX (MATLAB) build   (see Signals-Mex/)
//   pybind11::object      — Python binding stub   (see python/)
//
// ValueTraits<V> (value_traits.h) supplies all type-specific operations.
// Template bodies live in network_impl.h; only declarations are here.
// ---------------------------------------------------------------------------
template <typename V>
class NetworkT {
    using Traits = ValueTraits<V>;

private:
    template <typename> friend class NetFactory;

    class Node {
        friend class NetworkT;

        NetworkT* net{ nullptr };
        long id{ -1 };
        bool inUse{ false };
        bool queued{ false };
        bool appendValues{ false };
        TransfererT<V> transferer{ Operation::nop };
        std::vector<Node*> inputs;
        std::set<Node*> targets;
        std::optional<V> workingValue;  // nullopt = not fired this tick
        std::optional<V> currentValue;  // nullopt = never fired

    public:
        Node() = default;
        Node(NetworkT* t_net, long t_id, Operation t_op);
        void destroy();
        long get_id() const;
        bool operator==(const Node& other) const { return get_id() == other.get_id(); }
        bool is_valid() const { return inUse && net->is_valid(); }
        bool is_available() const { return !inUse; }
        void set_working_value(const V& value);
        void set_current_value(const V& value);
        void set_transferer(Operation t_op) { transferer = TransfererT<V>(t_op); }
        void set_callable(typename TransfererT<V>::NodeCallable fn) {
            transferer.set_callable(std::move(fn));
        }
        void set_inputs(std::vector<Node*> t_inputs);
        void add_target(Node* target) { targets.insert(target); }
        bool transfer();
    };

    long id{ -1 };
    bool active{ false };
    long max_nodes;
    std::vector<Node> nodes;

    Node* get_node(size_t idx);
    Node* next_free_node();
    NetworkT(long t_id, long t_max_nodes);

public:
    // Direct heap-allocation constructor — used by the MEX proxy layer.
    explicit NetworkT(long t_max_nodes) : NetworkT(0, t_max_nodes) { active = true; }

    using NodeCallable = typename TransfererT<V>::NodeCallable;

    long get_id() const { return id; }
    long get_max_nodes() const { return max_nodes; }
    bool is_valid() { return active; }
    size_t n_active_nodes();
    size_t n_nodes() { return nodes.size(); }

    long add_node(const std::vector<long>& t_inputs, Operation t_op,
                  bool t_appendValues, NodeCallable callable = nullptr);

    bool set_node_current_value(long node_id, const V& value);
    void destroy();
    bool delete_node(long node_id);

    std::vector<long> transact(long node_id, const V& value);
    void apply(const std::vector<long>& affected_ids);

    [[nodiscard]] V get_current_value(long node_id) const;
    [[nodiscard]] V get_working_value(long node_id) const;
    [[nodiscard]] V get_latest_value(long node_id) const;

    bool clear_working_value(long node_id);
    [[nodiscard]] std::vector<long> get_node_inputs(long node_id) const;
};

// Backward-compat alias for standalone / unit-test code.
using Network = NetworkT<signals::Value>;

#endif
