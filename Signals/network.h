#pragma once
#ifndef __NETWORK_H_INCLUDED__
#define __NETWORK_H_INCLUDED__

#ifdef SIGNALS_EXPORTS
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

#include "transferer.h"
#include "datawrapper.h"
#include <algorithm>
#include <set>

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
            Network* net;
            long id{ -1 };  // index within network
            bool inUse{ false };
            bool queued{ false };
            bool appendValues{ false };
            Transferer transferer = { 50 };
            std::vector<Node> inputs = {};  // todo should this be a vector of pointers?
            std::set<Node> targets = {};  // todo should this be a vector of pointers?
            DataContainer<int>* workingValue = { 0 };
            bool workingValueSet{ false };
            DataContainer<int>* currentValue = { 0 };
            bool currentValueSet{ false };
        public:
            Node(Network* t_net, long t_id, Operation t_op);
            void destroy();
            long get_id() const;
            bool operator==(const Node& other) const { return get_id() == other.get_id(); }
            bool operator<(const Node& other) const { return get_id() < other.get_id(); }  // for std::set
            bool is_valid() const { return inUse && net->is_valid(); }
            bool is_available() const { return !inUse; }
            void set_working_value(DataContainer<int>* value);
            void set_current_value(DataContainer<int>* value);
            void set_transferer(Operation t_op) { transferer = Transferer(t_op); }
            void set_inputs(const std::vector<Node>& t_inputs);
            void add_target(Node& target) { targets.insert(target); }
        };

    long id{ -1 };
    bool active{ false };
    long max_nodes;  // make size_t?
    std::vector<Node> nodes;
    Node* get_node(size_t idx); // todo make public but return const Node&
    Node* next_free_node();
    Network(long t_id, long t_max_nodes);

public:
    long get_id() const { return id; }
    long get_max_nodes() const { return max_nodes; }
    bool is_valid() { return active && 0 <= id && id <= NetFactory<Network>::MAX_NETWORKS; }
    size_t n_active_nodes();
    size_t n_nodes() { return nodes.size(); }
    long add_node(const std::vector<long>& t_inputs, Operation t_op, bool t_appendValues);
    void destroy();
    // void delete_node(size_t node);  // todo
    //std::vector<std::unique_ptr<Node>> transact(Node node, DataContainer<int> value);

};

#endif