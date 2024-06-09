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
Network::Network(int t_id, int t_max_nodes) {
    id = t_id;
    max_nodes = t_max_nodes;
    nodes.reserve(max_nodes);
};

void Network::add_node(size_t t_inputs[], int t_op, bool t_appendValues) {
    // todo
};

std::vector<std::unique_ptr<Node>> Network::transact(Node node, DataWrapper<int> value) {
    // todo
};


// Node methods
Node::Node(Network* t_net, Operation t_op) {
    net = t_net;
    transferer = Transferer(t_op);
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
