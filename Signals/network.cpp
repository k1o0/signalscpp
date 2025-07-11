// ConsoleApplication1.cpp : This file contains the 'main' function. Program execution begins and ends there.
// cpp 17

#include <iostream>
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
    std::vector<Network::Node> input_nodes;
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
            input_nodes.push_back(*input_node);
        }
    }
    node->set_inputs(input_nodes);
    return node->get_id();
};

//std::vector<std::unique_ptr<Node>> Network::transact(Node node, DataContainer<int> value) {
//    // todo
//};


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
	inputs.clear();  // clear input nodes
	targets.clear();  // clear target nodes
    delete workingValue;  // delete working value if it was allocated
    delete currentValue;  // delete current value if it was allocated
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

void Network::Node::set_working_value(DataContainer<int>* value) {
    workingValue = value;
    workingValueSet = true;
}

void Network::Node::set_current_value(DataContainer<int>* value) {
    currentValue = value;
    currentValueSet = true;
}

void Network::Node::set_inputs(const std::vector<Network::Node>& t_inputs) {
    inputs = t_inputs;
    inUse = true;  // mark as in use when inputs are set
    // for each input node, set the current node as a target
    for (auto& input_node : inputs) {
        if (!input_node.is_valid()) {
			std::cerr << "Error: Input node is not valid.\n";
			continue;  // todo move up and return whether or not inputs correctly set?
		}
        input_node.add_target(*this);  // add this node as a target to each input node
    }
};

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
