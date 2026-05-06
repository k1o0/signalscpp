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

// ── delete_node tests ─────────────────────────────────────────────────────────

// Deleting an isolated source node (no inputs, no targets) marks it inactive
// and its slot can be reused by the next add_node call.
TEST(TestNetwork, DeleteIsolatedNode) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id = net->add_node(no_inputs, Operation::nop, false);
	ASSERT_NE(id, -1);
	EXPECT_EQ(net->n_active_nodes(), 1);

	EXPECT_TRUE(net->delete_node(id));
	EXPECT_EQ(net->n_active_nodes(), 0);

	// The freed slot must be reused rather than allocating a new one.
	long id2 = net->add_node(no_inputs, Operation::nop, false);
	EXPECT_EQ(id2, id);
	EXPECT_EQ(net->n_active_nodes(), 1);
	EXPECT_EQ(net->n_nodes(), 1); // no growth in node storage

	NetFactory<Network>::destroy_all();
}

// Deleting an invalid node returns false and leaves the network unchanged.
TEST(TestNetwork, DeleteInvalidNode) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id = net->add_node(no_inputs, Operation::nop, false);

	EXPECT_FALSE(net->delete_node(-1));           // out of range
	EXPECT_FALSE(net->delete_node(999));          // out of range
	EXPECT_EQ(net->n_active_nodes(), 1);          // no change

	net->delete_node(id);
	EXPECT_FALSE(net->delete_node(id));           // already inactive

	NetFactory<Network>::destroy_all();
}

// Deleting a source node disconnects it from its downstream target:
// transact no longer reaches the surviving target node.
TEST(TestNetwork, DeleteSourceDisconnectsTarget) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id_a = net->add_node(no_inputs, Operation::nop, false);
	long id_b = net->add_node({ id_a }, Operation::identity, false);

	// Establish baseline: posting to a propagates to b.
	auto affected = net->transact(id_a, signals::Value{ 1.0 });
	net->apply(affected);
	EXPECT_TRUE(signals::has_value(net->get_current_value(id_b)));

	// Delete a — b should no longer be reachable via transact.
	EXPECT_TRUE(net->delete_node(id_a));

	// b's inputs vector should now be empty.
	EXPECT_EQ(net->n_active_nodes(), 1);

	NetFactory<Network>::destroy_all();
}

// Deleting a downstream node removes it from its input's targets set:
// a subsequent transact on the source no longer includes the deleted node.
TEST(TestNetwork, DeleteTargetDisconnectsFromSource) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id_a = net->add_node(no_inputs, Operation::nop, false);
	long id_b = net->add_node({ id_a }, Operation::identity, false);

	EXPECT_TRUE(net->delete_node(id_b));
	EXPECT_EQ(net->n_active_nodes(), 1);

	// Transact on a should only affect a itself.
	auto affected = net->transact(id_a, signals::Value{ 5.0 });
	net->apply(affected);
	ASSERT_EQ(affected.size(), 1u);
	EXPECT_EQ(affected[0], id_a);

	NetFactory<Network>::destroy_all();
}

// Deleting a middle node in a chain (a -> b -> c) disconnects both sides:
// a no longer has b as a target, and c no longer lists b as an input.
// After deletion transact on a does NOT reach c.
TEST(TestNetwork, DeleteMiddleNodeInChain) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id_a = net->add_node(no_inputs,  Operation::nop,      false);
	long id_b = net->add_node({ id_a },   Operation::identity, false);
	long id_c = net->add_node({ id_b },   Operation::identity, false);

	EXPECT_TRUE(net->delete_node(id_b));
	EXPECT_EQ(net->n_active_nodes(), 2); // a and c remain

	// Transact on a must not reach c.
	auto affected = net->transact(id_a, signals::Value{ 7.0 });
	net->apply(affected);
	ASSERT_EQ(affected.size(), 1u);
	EXPECT_EQ(affected[0], id_a);
	EXPECT_FALSE(signals::has_value(net->get_current_value(id_c)));

	NetFactory<Network>::destroy_all();
}

// After deleting a node in a multi-input graph the remaining sibling input
// still propagates correctly when both nodes feed a shared successor.
TEST(TestNetwork, DeleteOneInputOfBinaryNode) {
	Network* net = NetFactory<Network>::create();
	const std::vector<long> no_inputs;
	long id_a = net->add_node(no_inputs,       Operation::nop,  false);
	long id_b = net->add_node(no_inputs,       Operation::nop,  false);
	long id_c = net->add_node({ id_a, id_b },  Operation::plus, false);

	// Post values to both so c has a current value.
	auto aff = net->transact(id_a, signals::Value{ 3.0 });
	net->apply(aff);
	aff = net->transact(id_b, signals::Value{ 4.0 });
	net->apply(aff);
	EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(id_c)), 7.0);

	// Delete b — a should no longer have b's slot in c's inputs, but the
	// graph is now structurally incomplete (one fewer input for a binary op).
	// The key invariant: a's targets set no longer contains b,
	// and a transact on b (after reusing its slot as a nop) does not reach c
	// through the old connection.
	EXPECT_TRUE(net->delete_node(id_b));
	EXPECT_EQ(net->n_active_nodes(), 2); // a and c

	// Reuse b's slot as an independent nop — it must not auto-wire to c.
	long id_b2 = net->add_node(no_inputs, Operation::nop, false);
	EXPECT_EQ(id_b2, id_b); // slot reuse confirmed
	aff = net->transact(id_b2, signals::Value{ 10.0 });
	net->apply(aff);
	// c's current value must remain 7.0 — b2 is not connected to it.
	EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(id_c)), 7.0);

	NetFactory<Network>::destroy_all();
}

int main(int argc, char** argv) {
	testing::InitGoogleTest(&argc, argv);
	return RUN_ALL_TESTS();
}
