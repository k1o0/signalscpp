// test_transfer.cpp — unit tests for all core transfer functions (Group 1 & 2)
// and the appendValues accumulation path in apply().
#include "pch.h"
#include <gtest/gtest.h>
#include "../Signals/network.h"

// ── Fixture ───────────────────────────────────────────────────────────────────
// Each test gets a fresh network and tears it down afterwards.
class TransferTest : public ::testing::Test {
protected:
    Network* net = nullptr;
    void SetUp() override { net = NetFactory<Network>::create(); }
    void TearDown() override { NetFactory<Network>::destroy_all(); }

    // Convenience: post + commit in one call; return the committed value of id.
    signals::Value post(long id, const signals::Value& v) {
        auto aff = net->transact(id, v);
        net->apply(aff);
        return net->get_current_value(id);
    }

    // Post to id and return current value of result_id.
    signals::Value post_get(long src, const signals::Value& v, long result) {
        auto aff = net->transact(src, v);
        net->apply(aff);
        return net->get_current_value(result);
    }
};

// ── identity ─────────────────────────────────────────────────────────────────

TEST_F(TransferTest, IdentityPassesValue) {
    long a = net->add_node({},  Operation::nop,      false);
    long b = net->add_node({a}, Operation::identity, false);
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{3.14}, b)), 3.14);
}

// ── merge ─────────────────────────────────────────────────────────────────────

TEST_F(TransferTest, MergeFirstWins) {
    long a = net->add_node({},     Operation::nop,   false);
    long b = net->add_node({},     Operation::nop,   false);
    long m = net->add_node({a, b}, Operation::merge, false);

    // Only a fires — merge output should be a's value.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{1.0}, m)), 1.0);

    // Only b fires — merge output should be b's value.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{2.0}, m)), 2.0);
}

TEST_F(TransferTest, MergeBothInOneTick) {
    long a = net->add_node({},     Operation::nop,   false);
    long b = net->add_node({},     Operation::nop,   false);
    long m = net->add_node({a, b}, Operation::merge, false);

    // Post a first (lower BFS order) — merge must pick a's value.
    auto aff_a = net->transact(a, signals::Value{10.0});
    auto aff_b = net->transact(b, signals::Value{20.0});
    std::vector<long> all;
    all.insert(all.end(), aff_a.begin(), aff_a.end());
    all.insert(all.end(), aff_b.begin(), aff_b.end());
    net->apply(all);
    // m was included in aff_a; its working value was a's.
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(m)), 10.0);
}

// ── at_op ─────────────────────────────────────────────────────────────────────

TEST_F(TransferTest, AtOpFiresWhenGateTruthy) {
    long what = net->add_node({},          Operation::nop,   false);
    long when = net->add_node({},          Operation::nop,   false);
    long out  = net->add_node({what, when},Operation::at_op, false);

    // Set what's current value first (no gate yet).
    post(what, signals::Value{42.0});
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));

    // Gate fires with true → should pass what's latest (current) value through.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(when, signals::Value{true}, out)), 42.0);
}

TEST_F(TransferTest, AtOpSuppressedWhenGateFalsy) {
    long what = net->add_node({},           Operation::nop,   false);
    long when = net->add_node({},           Operation::nop,   false);
    long out  = net->add_node({what, when}, Operation::at_op, false);

    post(what, signals::Value{5.0});
    // Gate fires with false → no output.
    post_get(when, signals::Value{false}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── keep_when ────────────────────────────────────────────────────────────────

TEST_F(TransferTest, KeepWhenPassesOnNewWhatWhenGateTruthy) {
    long what = net->add_node({},            Operation::nop,       false);
    long when = net->add_node({},            Operation::nop,       false);
    long out  = net->add_node({what, when},  Operation::keep_when, false);

    // Set the gate to truthy via current.
    post(when, signals::Value{true});

    // Now what fires — gate is still truthy (latest = current) → output.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(what, signals::Value{7.0}, out)), 7.0);
}

TEST_F(TransferTest, KeepWhenSuppressedWhenGateFalsy) {
    long what = net->add_node({},            Operation::nop,       false);
    long when = net->add_node({},            Operation::nop,       false);
    long out  = net->add_node({what, when},  Operation::keep_when, false);

    post(when, signals::Value{false});
    post_get(what, signals::Value{9.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── latch ─────────────────────────────────────────────────────────────────────

TEST_F(TransferTest, LatchArmThenRelease) {
    long arm     = net->add_node({},          Operation::nop,   false);
    long release = net->add_node({},          Operation::nop,   false);
    long latch   = net->add_node({arm, release}, Operation::latch, false);

    // Arm → output: true.
    EXPECT_EQ(std::get<bool>(post_get(arm, signals::Value{true}, latch)), true);

    // Release → output: false.
    EXPECT_EQ(std::get<bool>(post_get(release, signals::Value{true}, latch)), false);
}

TEST_F(TransferTest, LatchNoOutputWithoutArm) {
    long arm     = net->add_node({},             Operation::nop,   false);
    long release = net->add_node({},             Operation::nop,   false);
    long latch   = net->add_node({arm, release}, Operation::latch, false);

    // Fire release without ever arming → no state change, no output.
    post_get(release, signals::Value{true}, latch);
    EXPECT_FALSE(signals::has_value(net->get_current_value(latch)));
}

// ── skip_repeats ──────────────────────────────────────────────────────────────

TEST_F(TransferTest, SkipRepeatsPassesFirstValue) {
    long src = net->add_node({},    Operation::nop,          false);
    long out = net->add_node({src}, Operation::skip_repeats, false);
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{3.0}, out)), 3.0);
}

TEST_F(TransferTest, SkipRepeatsSuppressesSameValue) {
    long src = net->add_node({},    Operation::nop,          false);
    long out = net->add_node({src}, Operation::skip_repeats, false);

    post_get(src, signals::Value{3.0}, out); // first — passes
    // Post same value again — working value equals current, suppress.
    auto aff = net->transact(src, signals::Value{3.0});
    net->apply(aff);
    // out's current should still be 3.0 but unchanged (suppress happened).
    // We verify via the affected list: out should NOT appear.
    EXPECT_EQ(std::find(aff.begin(), aff.end(), out), aff.end());
}

TEST_F(TransferTest, SkipRepeatsPassesDifferentValue) {
    long src = net->add_node({},    Operation::nop,          false);
    long out = net->add_node({src}, Operation::skip_repeats, false);

    post_get(src, signals::Value{3.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{4.0}, out)), 4.0);
}

// ── select_from ───────────────────────────────────────────────────────────────

TEST_F(TransferTest, SelectFromPicksCorrectOption) {
    long idx  = net->add_node({},              Operation::nop,         false);
    long opt0 = net->add_node({},              Operation::nop,         false);
    long opt1 = net->add_node({},              Operation::nop,         false);
    long out  = net->add_node({idx, opt0, opt1}, Operation::select_from, false);

    // Seed options first.
    post(opt0, signals::Value{10.0});
    post(opt1, signals::Value{20.0});

    // Index 0 → opt0.
    post(idx, signals::Value{0.0});
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 10.0);

    // Index 1 → opt1.
    post(idx, signals::Value{1.0});
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 20.0);
}

// ── function op (map / mapn / scan) ──────────────────────────────────────────

TEST_F(TransferTest, FunctionOpMap) {
    long src = net->add_node({},    Operation::nop,      false);
    long out = net->add_node({src}, Operation::function, false);

    // Double the input value.
    net->set_node_callable(out,
        [](const std::vector<signals::Value>& ins, const signals::Value&) -> signals::Value {
            return signals::Value{ std::get<double>(ins[0]) * 2.0 };
        });

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{6.0}, out)), 12.0);
}

TEST_F(TransferTest, FunctionOpMapn) {
    long a   = net->add_node({},     Operation::nop,      false);
    long b   = net->add_node({},     Operation::nop,      false);
    long out = net->add_node({a, b}, Operation::function, false);

    // Sum both inputs.
    net->set_node_callable(out,
        [](const std::vector<signals::Value>& ins, const signals::Value&) -> signals::Value {
            return signals::Value{ std::get<double>(ins[0]) + std::get<double>(ins[1]) };
        });

    post(a, signals::Value{3.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{4.0}, out)), 7.0);
}

TEST_F(TransferTest, FunctionOpScanAccumulates) {
    long item = net->add_node({},     Operation::nop,      false);
    long out  = net->add_node({item}, Operation::function, false);

    // Running sum (scan): accumulator + new item.
    net->set_node_callable(out,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc) -> signals::Value {
            const double prev = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return signals::Value{ prev + std::get<double>(ins[0]) };
        });

    post_get(item, signals::Value{1.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 1.0);
    post_get(item, signals::Value{2.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 3.0);
    post_get(item, signals::Value{10.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 13.0);
}

TEST_F(TransferTest, FunctionOpMonostateNoOutput) {
    long src = net->add_node({},    Operation::nop,      false);
    long out = net->add_node({src}, Operation::function, false);

    // Callable always returns monostate → no output committed.
    net->set_node_callable(out,
        [](const std::vector<signals::Value>&, const signals::Value&) -> signals::Value {
            return signals::Value{};
        });

    post_get(src, signals::Value{1.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── appendValues ─────────────────────────────────────────────────────────────

TEST_F(TransferTest, AppendValuesAccumulatesScalars) {
    long src = net->add_node({},    Operation::nop,      false);
    long acc = net->add_node({src}, Operation::identity, true); // appendValues=true

    post_get(src, signals::Value{1.0}, acc);
    post_get(src, signals::Value{2.0}, acc);
    post_get(src, signals::Value{3.0}, acc);

    signals::Value result = net->get_current_value(acc);
    const auto& v = std::get<std::vector<double>>(result);
    ASSERT_EQ(v.size(), 3u);
    EXPECT_DOUBLE_EQ(v[0], 1.0);
    EXPECT_DOUBLE_EQ(v[1], 2.0);
    EXPECT_DOUBLE_EQ(v[2], 3.0);
}

TEST_F(TransferTest, AppendValuesAccumulatesVectors) {
    long src = net->add_node({},    Operation::nop,      false);
    long acc = net->add_node({src}, Operation::identity, true);

    post_get(src, signals::Value{std::vector<double>{1.0, 2.0}}, acc);
    post_get(src, signals::Value{std::vector<double>{3.0, 4.0}}, acc);

    signals::Value result = net->get_current_value(acc);
    const auto& v = std::get<std::vector<double>>(result);
    ASSERT_EQ(v.size(), 4u);
    EXPECT_DOUBLE_EQ(v[2], 3.0);
    EXPECT_DOUBLE_EQ(v[3], 4.0);
}

// ── is_truthy ─────────────────────────────────────────────────────────────────

TEST(TestValueHelpers, IsTruthy) {
    EXPECT_FALSE(signals::is_truthy(signals::Value{}));           // monostate
    EXPECT_TRUE (signals::is_truthy(signals::Value{true}));
    EXPECT_FALSE(signals::is_truthy(signals::Value{false}));
    EXPECT_TRUE (signals::is_truthy(signals::Value{1.0}));
    EXPECT_FALSE(signals::is_truthy(signals::Value{0.0}));
    EXPECT_TRUE (signals::is_truthy(signals::Value{std::string{"hi"}}));
    EXPECT_FALSE(signals::is_truthy(signals::Value{std::string{""}}));
    EXPECT_TRUE (signals::is_truthy(signals::Value{std::vector<double>{0.0, 1.0}}));
    EXPECT_FALSE(signals::is_truthy(signals::Value{std::vector<double>{0.0, 0.0}}));
}

// ── values_equal ─────────────────────────────────────────────────────────────

TEST(TestValueHelpers, ValuesEqual) {
    EXPECT_TRUE (signals::values_equal(signals::Value{3.0},  signals::Value{3.0}));
    EXPECT_FALSE(signals::values_equal(signals::Value{3.0},  signals::Value{4.0}));
    EXPECT_TRUE (signals::values_equal(signals::Value{true},  signals::Value{true}));
    EXPECT_FALSE(signals::values_equal(signals::Value{true},  signals::Value{false}));
    EXPECT_TRUE (signals::values_equal(
        signals::Value{std::vector<double>{1.0, 2.0}},
        signals::Value{std::vector<double>{1.0, 2.0}}));
    EXPECT_FALSE(signals::values_equal(
        signals::Value{std::vector<double>{1.0, 2.0}},
        signals::Value{std::vector<double>{1.0, 3.0}}));
    // Type mismatch → not equal.
    EXPECT_FALSE(signals::values_equal(signals::Value{1.0}, signals::Value{true}));
}
