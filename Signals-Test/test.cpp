#include "pch.h"
#include <gtest/gtest.h>
#include "../Signals/network.h"
// todo make destroy all a tear down

TEST(TestNetwork, TestConstructor) {
	Network* net = NetFactory<Network>::create();
	ASSERT_NE(net, nullptr);
	EXPECT_EQ(net->get_id(), 0);
	EXPECT_TRUE(net->is_valid());
	EXPECT_TRUE(NetFactory<Network>::is_valid(net));
	NetFactory<Network>::destroy(0); // Clean up the created network
	EXPECT_FALSE(NetFactory<Network>::is_valid(net));
	Network* net2 = NetFactory<Network>::create();
	ASSERT_NE(net2, nullptr);
	EXPECT_EQ(net2->get_id(), 1); // todo change behaviour to reuse IDs
	Network* net3 = NetFactory<Network>::create();
	EXPECT_EQ(net3->get_id(), 2); // Should be the next available ID
	NetFactory<Network>::destroy(1); // Clean up the second network
	NetFactory<Network>::destroy(2);
	ASSERT_THROW(NetFactory<Network>::destroy(2), std::runtime_error); // Should throw since it's already destroyed
	NetFactory<Network>::destroy_all(); // Clean up all networks
}

TEST(NetFactoryTest, ExceedMaxNetworks) {
    // Create up to the maximum allowed
    // init vector to hold created networks using smart pointers to handle cleanup
    for (int i = 0; i < NetFactory<Network>::MAX_NETWORKS; ++i) {
        // Create new net and cast to unique_ptr before adding to the vector
		NetFactory<Network>::create();
    }
    // The next creation should throw
    ASSERT_THROW(NetFactory<Network>::create(), std::runtime_error);
	// Clean up networks
	NetFactory<Network>::destroy_all(); // Clean up all networks
}

TEST(TestNetwork, TestNodeCreation) {
	Network* net = NetFactory<Network>::create();
	ASSERT_NE(net, nullptr);
	EXPECT_EQ(net->n_active_nodes(), 0); // Initially no active nodes
	EXPECT_EQ(net->n_nodes(), 0); // Initially no nodes created
	// Create a node with no inputs
	const std::vector<long> no_inputs;
	long id = net->add_node(no_inputs, Operation::nop, false);
	ASSERT_NE(id, -1);
	EXPECT_EQ(net->n_active_nodes(), 1); // One active node now
	EXPECT_EQ(net->n_nodes(), 1); // One node created
	// Clean up the created network
	NetFactory<Network>::destroy(net->get_id());
	NetFactory<Network>::destroy_all(); // Clean up all networks
}


TEST(TestNetwork, ExceedMaxNodes) {
	Network* net = NetFactory<Network>::create();
	ASSERT_NE(net, nullptr);
	// Create many nodes
	const std::vector<long> no_inputs;
	for (int i = 0; i < net->get_max_nodes(); ++i) {
		long id = net->add_node(no_inputs, Operation::nop, false);
		ASSERT_NE(id, -1);
	}
	long id = net->add_node(no_inputs, Operation::nop, false);
	EXPECT_EQ(id, -1);
	// Clean up the created network
	NetFactory<Network>::destroy(net->get_id());
	NetFactory<Network>::destroy_all(); // Clean up all networks
}

TEST(TestNetwork, TestTransact) {
	Network* net = NetFactory<Network>::create();
	ASSERT_NE(net, nullptr);

	// Graph: a (nop) --> c = a + b <-- b (nop)
	const std::vector<long> no_inputs;
	long id_a = net->add_node(no_inputs, Operation::nop, false);
	long id_b = net->add_node(no_inputs, Operation::nop, false);
	std::vector<long> ab{ id_a, id_b };
	long id_c = net->add_node(ab, Operation::plus, false);
	ASSERT_NE(id_a, -1);
	ASSERT_NE(id_b, -1);
	ASSERT_NE(id_c, -1);

	// Post 3.0 to a — b has no value yet, so c cannot compute
	auto affected = net->transact(id_a, signals::Value{ 3.0 });
	net->apply(affected);
	EXPECT_FALSE(signals::has_value(net->get_current_value(id_c)));

	// Post 4.0 to b — now both inputs are available, c = 3 + 4 = 7
	affected = net->transact(id_b, signals::Value{ 4.0 });
	net->apply(affected);
	auto val_c = net->get_current_value(id_c);
	ASSERT_TRUE(signals::has_value(val_c));
	EXPECT_DOUBLE_EQ(std::get<double>(val_c), 7.0);

	// Update a to 10.0 — c should recompute using a=10, b=4 → 14
	affected = net->transact(id_a, signals::Value{ 10.0 });
	net->apply(affected);
	val_c = net->get_current_value(id_c);
	ASSERT_TRUE(signals::has_value(val_c));
	EXPECT_DOUBLE_EQ(std::get<double>(val_c), 14.0);

	NetFactory<Network>::destroy_all();
}

int main(int argc, char** argv) {
	testing::InitGoogleTest(&argc, argv);
	return RUN_ALL_TESTS();
}
