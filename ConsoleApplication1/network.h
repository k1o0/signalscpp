#pragma once
#ifndef __NETWORK_H_INCLUDED__
#define __NETWORK_H_INCLUDED__

#include "transferer.h"
#include "datawrapper.h"

// https://stackoverflow.com/a/28055997
// https://stackoverflow.com/a/56994812
// todo destroyNetworks
// todo check max networks, etc.
template <typename T>
class NetFactory {
private:
    inline static std::vector<std::unique_ptr<T>> networks = {};

public:
    static const int MAX_NETWORKS{ 10 };
    static T* create() {
        std::unique_ptr<T> obj{ new T(networks.size(), int(4000)) };
        obj->id = networks.size();
        obj->active = true;
        networks.emplace_back(std::move(obj));
        return networks.back().get();
    };

    //static T* get(size_t idx) const {
    //    return networks[idx].get();
    //}
};


class Node;


class Network {
private:
    friend class NetFactory<Network>;
    int id{ -1 };
    bool active{ false };
    int max_nodes;  // make size_t?
    std::vector<std::unique_ptr<Node>> nodes;
    Network(int t_id, int t_max_nodes);
public:
    int get_id() { return id; };
    bool is_valid() { return active && 0 <= id && id <= NetFactory<Network>::MAX_NETWORKS; };
    int n_nodes() { return 0; };  // todo
    void add_node(size_t t_inputs[], int t_op, bool t_appendValues);
    void delete_node(size_t node);
    std::vector<std::unique_ptr<Node>> transact(Node node, DataWrapper<int> value);
};


// todo needs to be a template to handle different value types
class Node {
private:
    Network* net;
    int id{ -1 };
    bool inUse{ false };
    bool queued{ false };
    bool appendValues{ false };
    Transferer transferer = { 50 };
    std::vector<Node> inputs = {};
    std::vector<Node> targets = {};
public:
    Node(Network* t_net, Operation t_op);
    int get_id() { return id; };
    bool is_valid() { return inUse && net->is_valid(); };

};

#endif