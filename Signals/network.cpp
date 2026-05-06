// ConsoleApplication1.cpp : This file contains the 'main' function. Program execution begins and ends there.
// cpp 17

#include <iostream>
#include <queue>
#include <set>
#include <vector>
#include "network.h"




//// Networks fixed-size array
//template <typename T>
//class NetFactory {
//private:
//    inline static T networks[NetFactory<T>::MAX_NETWORKS];
//    static T* arrEnd{ nullptr };
//public:
//    static const int MAX_NETWORKS{ 10 };
//    static T* create() {
//        if (arrEnd) { // array not empty
//            int i = 0;
//            for (const T& net : networks) { // first free net
//                if (!net->active) { break; }
//                i++;
//            }
//            if (net->active && i == NetFactory<T>::MAX_NETWORKS) {
//                // all networks in use
//            }
//            else if (net->active) {
//                // create new net in the next slot
//            }
//            else {
//                // replace current net
//            }
//        }
//        else {
//            ;
//        }
//        std::unique_ptr<T> obj{ new T(networks.size(), int(4000)) };
//        obj->id = networks.size();
//        obj->active = true;
//        networks.emplace_back(std::move(obj));
//        return networks.back().get();
//    }
//
//    //static T* get(size_t idx) const {
//    //    return networks[idx].get();
//    //}
//};


// Network methods
Network::Network(long t_id, long t_max_nodes) {
    id = t_id;
    max_nodes = t_max_nodes;
    nodes.reserve(max_nodes);
};


void Network::destroy() {
    NetFactory<Network>::destroy(id);
}

/// <summary>
/// Get the number of active nodes in the network.
/// </summary>
/// <returns>The number of active nodes.</returns>
size_t Network::n_active_nodes() {
	size_t count = 0;
	for (const auto& node : nodes) {
		if (node.is_valid()) count++;
	}
	return count;
}

/// <summary>
/// Get the next free node in the network.
/// This will return the first available node that is not in use, or create one
/// if there are no free nodes and the maximum number of nodes has not been reached.
/// </summary>
/// <returns>A pointer to the next free node.</returns>
Network::Node* Network::next_free_node() {
    // check if there are any free nodes
    for (size_t i = 0; i < nodes.size(); i++) {
        if (nodes[i].is_available()) { return &nodes[i]; }  // return the first available node
    }
    // if no free nodes, check if we can create a new one
    if (nodes.size() < max_nodes) {
        // if no free nodes, but we can add more, create a new node
        Network::Node node(this, static_cast<long>(this->nodes.size()), Operation::nop);  // create a new node with no operation
        nodes.emplace_back(std::move(node));  // add the new node to the network
        return &nodes.back();  // return a pointer to the newly created node
    }
    // // no free nodes available and maximum reached
    std::cerr << "Error: Maximum number of nodes reached. Cannot add more nodes.\n";
	return nullptr;
}

/// <summary>
/// Get a node by its index.
/// </summary>
/// <param name="idx">The index of the node.</param>
/// <returns>A pointer to the node, or nullptr if the index is out of range.</returns>
Network::Node* Network::get_node(size_t idx) {
    if (idx >= nodes.size()) {
        std::cerr << "Error: Node index out of range\n";
        return nullptr;
    }
    return &nodes[idx];
};

/// <summary>
/// Add a node to the network.
/// </summary>
/// <param name="t_inputs">A vector of input node IDs.</param>
/// <param name="t_op">The operation code to appy.</param>
/// <param name="t_appendValues">Whether store new values in an array.</param>
/// <returns>The index of the newly added node.</returns>
long Network::add_node(const std::vector<long>& t_inputs, Operation t_op, bool t_appendValues) {
    Network::Node* node = next_free_node();
    if (!node) {
        std::cerr << "Error: No free nodes available in the network.\n";
        return -1;
    }
    node->set_transferer(t_op);
    std::vector<Network::Node*> input_nodes;
    for (const long& input_id : t_inputs) {
        if (input_id < 0 || input_id >= static_cast<long>(n_nodes())) {
			std::cerr << "Error: Input node index " << input_id << " is out of range.\n";
			return -1;  // return an error code if the input index is out of range
		}
        Network::Node* input_node = get_node(static_cast<size_t>(input_id));
        if (!input_node) {
            std::cerr << "Error: Input node with index " << input_id << " does not exist.\n";
            return -1;
        } else if (!input_node->is_valid()) {
            std::cerr << "Error: Input node with index " << input_id << " is not valid.\n";
            return -1;
        } else {
            std::cout << "node " << input_id << "->" << node->get_id() << ".\n";
            input_nodes.push_back(input_node);
        }
    }
    node->set_inputs(std::move(input_nodes));
    return node->get_id();
};

/// Disconnect and deactivate a node, freeing its slot for reuse.
/// For each input of this node, removes the node from that input's targets set.
/// For each target of this node, removes the node from that target's inputs vector.
/// Then calls destroy() to clear the node's own state and mark it as available.
/// Returns false if node_id is out of range or the node is not active.
/// Legacy analogue: cleanupNode(disconnect=true) in network.c
bool Network::delete_node(long node_id) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) {
        std::cerr << "Error: delete_node: node ID " << node_id << " out of range.\n";
        return false;
    }
    Node* node = &nodes[static_cast<size_t>(node_id)];
    if (!node->inUse) {
        std::cerr << "Error: delete_node: node " << node_id << " is not active.\n";
        return false;
    }

    // Remove this node as a target from each of its input nodes.
    for (Node* input : node->inputs) {
        input->targets.erase(node);
    }

    // Remove this node as an input from each of its target nodes.
    for (Node* target : node->targets) {
        auto& inp = target->inputs;
        inp.erase(std::remove(inp.begin(), inp.end(), node), inp.end());
    }

    // Clear this node's own connections and mark it as available.
    node->destroy();
    return true;
}

/// Post a new value to a source node and propagate through the graph via BFS.
/// The queued flag on each Node deduplicates entries so no node appears in the
/// work queue twice within one transaction — matching the QUEUE_PUT behaviour
/// in the legacy network.c.
/// Returns IDs of all affected nodes (working value updated), in visitation order.
std::vector<long> Network::transact(long node_id, const signals::Value& value) {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size()) {
        std::cerr << "Error: transact: node ID " << node_id << " out of range.\n";
        return {};
    }
    Node* node = &nodes[static_cast<size_t>(node_id)];
    if (!node->is_valid()) {
        std::cerr << "Error: transact: node " << node_id << " is not valid.\n";
        return {};
    }

    std::vector<long> affected;
    std::queue<Node*> todo;

    node->set_working_value(value);
    affected.push_back(node_id);

    for (Node* t : node->targets) {
        if (!t->queued) { t->queued = true; todo.push(t); }
    }

    while (!todo.empty()) {
        Node* curr = todo.front();
        todo.pop();
        curr->queued = false;

        if (curr->transfer()) {
            affected.push_back(curr->get_id());
            for (Node* t : curr->targets) {
                if (!t->queued) { t->queued = true; todo.push(t); }
            }
        }
    }
    return affected;
}

/// Commit working values from transact() into current values and clear working state.
/// Legacy analogue: the working->current loop inside sqApply() in network.c
void Network::apply(const std::vector<long>& affected_ids) {
    for (long nid : affected_ids) {
        if (nid < 0 || static_cast<size_t>(nid) >= nodes.size()) continue;
        Node& n = nodes[static_cast<size_t>(nid)];
        if (signals::has_value(n.workingValue)) {
            n.currentValue = std::move(n.workingValue);
            n.currentValueSet = true;
            n.workingValue = signals::Value{};  // reset to monostate
            n.workingValueSet = false;
        }
    }
}

/// Return the committed current value of a node, or monostate if it has none.
signals::Value Network::get_current_value(long node_id) const {
    if (node_id < 0 || static_cast<size_t>(node_id) >= nodes.size())
        return signals::Value{};
    return nodes[static_cast<size_t>(node_id)].currentValue;
}


// Node methods
Network::Node::Node(Network* t_net, long t_id, Operation t_op) {
    // assert that the network is valid
    if (!t_net || !t_net->is_valid()) {
        std::cerr << "Error: Network is not valid.\n";
        return;  // exit if the network is not valid
    }
    net = t_net;
    id = t_id;
    transferer = Transferer(t_op);
}

void Network::Node::destroy() {
	inUse = false;  // mark the node as not in use
	queued = false;  // mark the node as not queued
	workingValueSet = false;  // reset working value flag
	currentValueSet = false;  // reset current value flag
	workingValue = signals::Value{};  // reset to monostate
	currentValue = signals::Value{};  // reset to monostate
	inputs.clear();  // clear input nodes
	targets.clear();  // clear target nodes
}

long Network::Node::get_id() const {
	// return the index of the node in the network
    if (!net || !net->is_valid()) {
		std::cerr << "Error: Network is not valid.\n";
		return -1;  // return an invalid id if the network is not valid
	}
	if (id < 0 || id > static_cast<long>(net->n_nodes())) {
		std::cerr << "Error: Node ID is out of range.\n";
		return -1;  // return an invalid id if the id is out of range
	}
	return id;
}

void Network::Node::set_working_value(const signals::Value& value) {
    workingValue = value;
    workingValueSet = true;
}

void Network::Node::set_current_value(const signals::Value& value) {
    currentValue = value;
    currentValueSet = true;
}

void Network::Node::set_inputs(std::vector<Network::Node*> t_inputs) {
    inputs = std::move(t_inputs);
    inUse = true;  // mark as in use when inputs are set
    // for each input node, register this node as a target on the real instance
    for (Node* input_node : inputs) {
        if (!input_node->is_valid()) {
			std::cerr << "Error: Input node is not valid.\n";
			continue;
		}
        input_node->add_target(this);
    }
};

/// Recompute this node's working value from its inputs' latest values and
/// return true when propagation to targets should continue.
///
/// "Latest value" for an input = its working value if set, otherwise its
/// current value. This mirrors the LATEST_VALUE macro in legacy network.c.
///
/// Propagation rules (matching legacy transfer() in network.c):
///   1. New output produced  → store as working value, return true.
///   2. New output unset, working was previously set → clear working, return
///      true (downstream nodes must learn this node's value was lost).
///   3. New output unset, working was also unset → return false (no change).
bool Network::Node::transfer() {
    const int op_int = static_cast<int>(transferer.get_op());
    const Operation op = transferer.get_op();

    // LATEST_VALUE: prefer working value; fall back to current value.
    auto latest = [](const Node* n) -> const signals::Value& {
        return signals::has_value(n->workingValue) ? n->workingValue : n->currentValue;
    };

    bool produced_output = false;

    if (op_int > 0 && op_int < 20) {  // binary ops: plus(1)...eq(14)
        if (inputs.size() >= 2 &&
            (signals::has_value(inputs[0]->workingValue) ||
             signals::has_value(inputs[1]->workingValue))) {
            const signals::Value& lv = latest(inputs[0]);
            const signals::Value& rv = latest(inputs[1]);
            if (signals::has_value(lv) && signals::has_value(rv)) {
                try {
                    signals::Value result;  // defaults to monostate
                    switch (op) {
                        case Operation::plus:    result = signals::add(lv, rv);      break;
                        case Operation::minus:   result = signals::subtract(lv, rv); break;
                        case Operation::mtimes:  result = signals::multiply(lv, rv); break;
                        case Operation::rdivide: result = signals::rdivide(lv, rv);  break;
                        case Operation::mdivide: result = signals::ldivide(lv, rv);  break;
                        case Operation::gt:      result = signals::gt(lv, rv);       break;
                        case Operation::ge:      result = signals::ge(lv, rv);       break;
                        case Operation::lt:      result = signals::lt(lv, rv);       break;
                        case Operation::le:      result = signals::le(lv, rv);       break;
                        case Operation::eq:      result = signals::eq(lv, rv);       break;
                        default: break;  // unknown: leave result as monostate
                    }
                    if (signals::has_value(result)) {
                        workingValue = std::move(result);
                        workingValueSet = true;
                        produced_output = true;
                    }
                } catch (const signals::TypeError&) {
                    // type mismatch — treat as unset output, fall through
                }
            }
        }
    } else if (op == Operation::identity) {
        // Pass the first input's working value through unchanged.
        if (!inputs.empty() && signals::has_value(inputs[0]->workingValue)) {
            workingValue = inputs[0]->workingValue;
            workingValueSet = true;
            produced_output = true;
        }
    }
    // nop (51) / function (0): source nodes — transact() sets their value
    // directly, transfer() is never meaningfully called on them.

    if (produced_output) return true;

    // New output is unset.  Propagate if the working value was previously set
    // so downstream nodes learn this node's value disappeared.
    if (signals::has_value(workingValue)) {
        workingValue = signals::Value{};
        workingValueSet = false;
        return true;
    }
    return false;
}

int main()
{
    Network* net = NetFactory<Network>::create();
    Network* net2 = NetFactory<Network>::create();
    //Network* net = NetFactory<Network>::foo();
    //Network net(5);
    //std::cout << "net id: " << net.get_id() << std::endl;
    //auto sz = NetFactory<Network>::networks.size();
    std::cout << "max networks: " << NetFactory<Network>::MAX_NETWORKS << std::endl;
    std::cout << "net1 id: " << net->get_id() << std::endl;
    std::cout << "net1 active: " << net->is_valid() << std::endl;
    std::cout << "net2 id: " << net2->get_id() << std::endl;
    // add a few nodes to the network
    // add node with no inputs
    const std::vector<long> no_inputs;
    long id = net->add_node(no_inputs, Operation::nop, false);
    std::cout << "node1 id: " << id << std::endl;
    long id2 = net->add_node(no_inputs, Operation::nop, false);
    std::cout << "node2 id: " << id2 << std::endl;
    // add node with one input
    std::vector <long> inputs{ id, id2 };
    long id3 = net->add_node(inputs, Operation::plus, false);
    std::cout << "node3 id: " << id3 << std::endl;
    std::cout << "Number of nodes in net: " << net->n_active_nodes() << std::endl;
    return 0;
}


/*
// Factory pattern
class Factory {
  list<shared_ptr<Monster>> listOfMonsters;
public:
  void UpdateAllMonsters() {
    for(auto pMonster : listOfMonsters)  {
      monster->Update();
    }
  }

  shared_ptr<Monster> createMonster() {
    auto newMonster = make_shared<Monster>();
    listOfMonsters.push_back(newMonster);
    return newMonster;
  }
};

class Monster {
  shared_ptr<Factory> theFactory;
public:
  void Update() {
    auto newMonster = theFactory->createMonster();
    // ...
  }
};


// example: class constructor
#include <iostream>
using namespace std;

class Rectangle {
    int width, height;
public:
    Rectangle(int, int);
    int area() { return (width * height); }
};

Rectangle::Rectangle(int a, int b) {
    width = a;
    height = b;
}

int main() {
    Rectangle rect(3, 4);
    Rectangle rectb(5, 6);
    cout << "rect area: " << rect.area() << endl;
    cout << "rectb area: " << rectb.area() << endl;
    return 0;
}
*/
// Run program: Ctrl + F5 or Debug > Start Without Debugging menu
// Debug program: F5 or Debug > Start Debugging menu

// Tips for Getting Started:
//   1. Use the Solution Explorer window to add/manage files
//   2. Use the Team Explorer window to connect to source control
//   3. Use the Output window to see build output and other messages
//   4. Use the Error List window to view errors
//   5. Go to Project > Add New Item to create new code files, or Project > Add Existing Item to add existing code files to the project
//   6. In the future, to open this project again, go to File > Open > Project and select the .sln file
