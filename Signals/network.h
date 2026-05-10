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
#include "value.h"
#include <algorithm>
#include <functional>
#include <memory>
#include <set>
#include <vector>

constexpr int CORE_LIB_VERSION_MAJOR = 0;
constexpr int CORE_LIB_VERSION_MINOR = 1;
constexpr int CORE_LIB_VERSION_PATCH = 0;

// https://stackoverflow.com/a/28055997
// https://stackoverflow.com/a/56994812
// todo destroyNetworks
// todo check max networks, etc.
// todo id currectly combo of size_t and long; should change to std::optional unsigned int
template <typename T>
class NetFactory {
private:
    inline static std::vector<std::unique_ptr<T>> networks = {};

public:
    static const int MAX_NETWORKS{ 10 };
    static T* create() {
        // todo handle invalid networks in the vector
        // this could be done by looking up pointer rather than using index
        // or by using a map with unique_ptr
        if (networks.size() >= MAX_NETWORKS) {
			// all networks in use, return nullptr or throw an exception
			throw std::runtime_error("Maximum number of networks reached");
		}
        std::unique_ptr<T> obj{ new T(networks.size(), long(4000)) };  // todo make max nodes a parameter
        obj->id = networks.size();
        obj->active = true;
        networks.emplace_back(std::move(obj));
        return networks.back().get();
    }

    static void destroy(long id) {
        // cast ID to size_t for indexing
        if (id < 0 || id >= static_cast<long>(networks.size())) {
			throw std::out_of_range("Network index out of range");
		}
        size_t idx = static_cast<size_t>(id);
        if (idx < networks.size()) {
            if (!networks[idx]) {
				throw std::runtime_error("Network already destroyed or invalid");
			}
            networks[idx]->active = false;  // mark as inactive
            for (auto& node : networks[idx]->nodes) {
				node.destroy();  // call destroy on each node
			}
            networks[idx]->nodes.clear();  // clear nodes
            networks[idx].reset();  // release the unique_ptr
            // Remove the unique_ptr from the vector
            // networks.erase(networks.begin() + idx);
        }
    }

    static size_t destroy_all() {
        size_t n_destroyed = 0;  // count of destroyed networks
		for (auto& net : networks) {
			if (net) {
                n_destroyed++;
				NetFactory<T>::destroy(net->get_id());  // call destroy on each network
			}
		}
		networks.clear();  // clear all networks
		return n_destroyed;
	}

    static bool is_valid(T* net) {
        return std::any_of(networks.begin(), networks.end(),
            [net](const std::unique_ptr<T>& ptr) { return ptr.get() == net; });
    }
};


class SIGNALS_API Network {
private:
    friend class NetFactory<Network>;

    class SIGNALS_API Node {
        private:
            friend class Network;  // Network::transact needs access to private members
            Network* net;
            long id{ -1 };  // index within network
            bool inUse{ false };
            bool queued{ false };
            bool appendValues{ false };
            Transferer transferer{ Operation::nop };
            std::vector<Node*> inputs = {};
            std::set<Node*> targets = {};
            signals::Value workingValue{};
            bool workingValueSet{ false };
            signals::Value currentValue{};
            bool currentValueSet{ false };
        public:
            Node(Network* t_net, long t_id, Operation t_op);
            void destroy();
            long get_id() const;
            bool operator==(const Node& other) const { return get_id() == other.get_id(); }
            bool is_valid() const { return inUse && net->is_valid(); }
            bool is_available() const { return !inUse; }
            void set_working_value(const signals::Value& value);
            void set_current_value(const signals::Value& value);
            void set_transferer(Operation t_op) { transferer = Transferer(t_op); }
            void set_callable(Transferer::NodeCallable fn) {
                transferer.set_callable(std::move(fn));
            }
            void set_inputs(std::vector<Node*> t_inputs);
            void add_target(Node* target) { targets.insert(target); }
            // Recompute working value from inputs. Returns true when output may
            // have changed and propagation should continue to targets.
            // Legacy analogue: transfer() in network.c
            bool transfer();
        };

    long id{ -1 };
    bool active{ false };
    long max_nodes;  // make size_t?
    std::vector<Node> nodes;
    Node* get_node(size_t idx); // todo make public but return const Node&
    Node* next_free_node();
    // Used by NetFactory (passes an assigned ID).
    Network(long t_id, long t_max_nodes);

public:
    // Direct heap-allocation constructor — used by the MEX proxy layer.
    // id is set to 0 and active to true immediately.
    explicit Network(long t_max_nodes) : Network(0, t_max_nodes) { active = true; }

    // NodeCallable is the single callable type used by all opcode-driven nodes.
    // Defined in Transferer (transferer.h); aliased here for callers that reach
    // it via the Network:: scope (e.g., mx_ops, NetworkProxy).
    using NodeCallable = Transferer::NodeCallable;

    long get_id() const { return id; }
    long get_max_nodes() const { return max_nodes; }
    bool is_valid() { return active; }
    size_t n_active_nodes();
    size_t n_nodes() { return nodes.size(); }
    // Create a new node and optionally attach a callable in one step.
    // Pass callable = nullptr (default) for pure-C++ opcode nodes.
    long add_node(const std::vector<long>& t_inputs, Operation t_op,
                  bool t_appendValues, NodeCallable callable = nullptr);

    // Set the current (committed) value of a node directly.
    // Used by the binding layer to seed the accumulator of scan_op nodes
    // before the first transact.  Also useful for testing.
    bool set_node_current_value(long node_id, const signals::Value& value);
    void destroy();
    // Disconnect and deactivate a node, freeing its slot for reuse.
    // Removes the node as a target from each of its inputs, and removes it
    // as an input from each of its targets.
    // Legacy analogue: sqDeleteNode / cleanupNode(disconnect=true) in network.c
    bool delete_node(long node_id);
    // Post value to node, propagate through graph via BFS.
    // Returns IDs of all affected nodes — pass directly to apply().
    // Legacy analogues: transact() + sqTransact() in network.c
    std::vector<long> transact(long node_id, const signals::Value& value);
    // Commit working values produced by transact() into current values.
    // Legacy analogue: sqApply() in network.c
    void apply(const std::vector<long>& affected_ids);
    // Read the current (committed) value of a node.
    [[nodiscard]] signals::Value get_current_value(long node_id) const;
    // Read the working value of a node (set during transact, before apply).
    [[nodiscard]] signals::Value get_working_value(long node_id) const;
    // Read the latest value: working if set during transact, else current.
    [[nodiscard]] signals::Value get_latest_value(long node_id) const;
    // Reset the working value of a node to monostate.
    bool clear_working_value(long node_id);
    // Return the input node IDs of a node (for debug / introspection).
    [[nodiscard]] std::vector<long> get_node_inputs(long node_id) const;

};

#endif