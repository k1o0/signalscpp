// test_transfer.cpp — unit tests for all core transfer functions and network ops.
#include "pch.h"
#include <gtest/gtest.h>
#include "../Signals/network.h"

// ── Fixture ───────────────────────────────────────────────────────────────────
class TransferTest : public ::testing::Test {
protected:
    Network* net = nullptr;
    void SetUp() override { net = NetFactory<Network>::create(); }
    void TearDown() override { NetFactory<Network>::destroy_all(); }

    // Post + commit in one call; return the committed value of id.
    signals::Value post(long id, const signals::Value& v) {
        auto aff = net->transact(id, v);
        net->apply(aff);
        return net->get_current_value(id);
    }

    // Post to src and return current value of result.
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

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{1.0}, m)), 1.0);
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{2.0}, m)), 2.0);
}

TEST_F(TransferTest, MergeBothInOneTick) {
    long a = net->add_node({},     Operation::nop,   false);
    long b = net->add_node({},     Operation::nop,   false);
    long m = net->add_node({a, b}, Operation::merge, false);

    auto aff_a = net->transact(a, signals::Value{10.0});
    auto aff_b = net->transact(b, signals::Value{20.0});
    std::vector<long> all;
    all.insert(all.end(), aff_a.begin(), aff_a.end());
    all.insert(all.end(), aff_b.begin(), aff_b.end());
    net->apply(all);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(m)), 10.0);
}

// ── at_op ─────────────────────────────────────────────────────────────────────

TEST_F(TransferTest, AtOpFiresWhenGateTruthy) {
    long what = net->add_node({},           Operation::nop,   false);
    long when = net->add_node({},           Operation::nop,   false);
    long out  = net->add_node({what, when}, Operation::at_op, false);

    post(what, signals::Value{42.0});
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(when, signals::Value{true}, out)), 42.0);
}

TEST_F(TransferTest, AtOpSuppressedWhenGateFalsy) {
    long what = net->add_node({},           Operation::nop,   false);
    long when = net->add_node({},           Operation::nop,   false);
    long out  = net->add_node({what, when}, Operation::at_op, false);

    post(what, signals::Value{5.0});
    post_get(when, signals::Value{false}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── keep_when ────────────────────────────────────────────────────────────────

TEST_F(TransferTest, KeepWhenPassesOnNewWhatWhenGateTruthy) {
    long what = net->add_node({},           Operation::nop,       false);
    long when = net->add_node({},           Operation::nop,       false);
    long out  = net->add_node({what, when}, Operation::keep_when, false);

    post(when, signals::Value{true});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(what, signals::Value{7.0}, out)), 7.0);
}

TEST_F(TransferTest, KeepWhenSuppressedWhenGateFalsy) {
    long what = net->add_node({},           Operation::nop,       false);
    long when = net->add_node({},           Operation::nop,       false);
    long out  = net->add_node({what, when}, Operation::keep_when, false);

    post(when, signals::Value{false});
    post_get(what, signals::Value{9.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── latch ─────────────────────────────────────────────────────────────────────

TEST_F(TransferTest, LatchArmThenRelease) {
    long arm     = net->add_node({},            Operation::nop,   false);
    long release = net->add_node({},            Operation::nop,   false);
    long latch   = net->add_node({arm, release}, Operation::latch, false);

    EXPECT_EQ(std::get<bool>(post_get(arm, signals::Value{true}, latch)), true);
    EXPECT_EQ(std::get<bool>(post_get(release, signals::Value{true}, latch)), false);
}

TEST_F(TransferTest, LatchNoOutputWithoutArm) {
    long arm     = net->add_node({},             Operation::nop,   false);
    long release = net->add_node({},             Operation::nop,   false);
    long latch   = net->add_node({arm, release}, Operation::latch, false);

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

    post_get(src, signals::Value{3.0}, out);
    auto aff = net->transact(src, signals::Value{3.0});
    net->apply(aff);
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
    long idx  = net->add_node({},               Operation::nop,         false);
    long opt0 = net->add_node({},               Operation::nop,         false);
    long opt1 = net->add_node({},               Operation::nop,         false);
    long out  = net->add_node({idx, opt0, opt1}, Operation::select_from, false);

    post(opt0, signals::Value{10.0});
    post(opt1, signals::Value{20.0});

    post(idx, signals::Value{0.0});
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 10.0);

    post(idx, signals::Value{1.0});
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 20.0);
}

// ── Arithmetic ops (1–5) ──────────────────────────────────────────────────────
// Value-level correctness is covered in test_value.cpp.
// These tests verify network gating: both inputs must have a value before output.

TEST_F(TransferTest, ArithPlusGatingAndResult) {
    long a   = net->add_node({},     Operation::nop,  false);
    long b   = net->add_node({},     Operation::nop,  false);
    long out = net->add_node({a, b}, Operation::plus, false);

    // a seeded — b has no value yet → no output
    post(a, signals::Value{3.0});
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));

    // b fires → both available → 3 + 4 = 7
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{4.0}, out)), 7.0);

    // a fires again using latest b → 5 + 4 = 9
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{5.0}, out)), 9.0);
}

TEST_F(TransferTest, ArithMinusResult) {
    long a   = net->add_node({},     Operation::nop,   false);
    long b   = net->add_node({},     Operation::nop,   false);
    long out = net->add_node({a, b}, Operation::minus, false);

    post(a, signals::Value{10.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{3.0}, out)), 7.0);
}

TEST_F(TransferTest, ArithMtimesResult) {
    long a   = net->add_node({},     Operation::nop,    false);
    long b   = net->add_node({},     Operation::nop,    false);
    long out = net->add_node({a, b}, Operation::mtimes, false);

    post(a, signals::Value{3.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{4.0}, out)), 12.0);
}

TEST_F(TransferTest, ArithRdivideResult) {
    long a   = net->add_node({},     Operation::nop,     false);
    long b   = net->add_node({},     Operation::nop,     false);
    long out = net->add_node({a, b}, Operation::rdivide, false);

    post(a, signals::Value{12.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{3.0}, out)), 4.0);
}

TEST_F(TransferTest, ArithMdivideResult) {
    // mdivide maps to ldivide: (a, b) → b / a
    long a   = net->add_node({},     Operation::nop,     false);
    long b   = net->add_node({},     Operation::nop,     false);
    long out = net->add_node({a, b}, Operation::mdivide, false);

    post(a, signals::Value{4.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{12.0}, out)), 3.0);
}

// ── Comparison ops (10–14) ───────────────────────────────────────────────────

TEST_F(TransferTest, CompareGtResult) {
    long a   = net->add_node({},     Operation::nop, false);
    long b   = net->add_node({},     Operation::nop, false);
    long out = net->add_node({a, b}, Operation::gt,  false);

    post(a, signals::Value{5.0});
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{3.0}, out)), true);
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{7.0}, out)), false);
}

TEST_F(TransferTest, CompareGeResult) {
    long a   = net->add_node({},     Operation::nop, false);
    long b   = net->add_node({},     Operation::nop, false);
    long out = net->add_node({a, b}, Operation::ge,  false);

    post(a, signals::Value{5.0});
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{5.0}, out)), true);
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{6.0}, out)), false);
}

TEST_F(TransferTest, CompareLtResult) {
    long a   = net->add_node({},     Operation::nop, false);
    long b   = net->add_node({},     Operation::nop, false);
    long out = net->add_node({a, b}, Operation::lt,  false);

    post(a, signals::Value{3.0});
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{5.0}, out)), true);
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{1.0}, out)), false);
}

TEST_F(TransferTest, CompareLeResult) {
    long a   = net->add_node({},     Operation::nop, false);
    long b   = net->add_node({},     Operation::nop, false);
    long out = net->add_node({a, b}, Operation::le,  false);

    post(a, signals::Value{3.0});
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{3.0}, out)), true);
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{2.0}, out)), false);
}

TEST_F(TransferTest, CompareEqResult) {
    long a   = net->add_node({},     Operation::nop, false);
    long b   = net->add_node({},     Operation::nop, false);
    long out = net->add_node({a, b}, Operation::eq,  false);

    post(a, signals::Value{7.0});
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{7.0}, out)), true);
    EXPECT_EQ(std::get<bool>(post_get(b, signals::Value{8.0}, out)), false);
}

// ── numel (30) ────────────────────────────────────────────────────────────────

TEST_F(TransferTest, NumelScalarGivesOne) {
    long src = net->add_node({},    Operation::nop,   false);
    long out = net->add_node({src}, Operation::numel, false);
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{42.0}, out)), 1.0);
}

TEST_F(TransferTest, NumelVectorGivesLength) {
    long src = net->add_node({},    Operation::nop,   false);
    long out = net->add_node({src}, Operation::numel, false);
    signals::Value v{std::vector<double>{1.0, 2.0, 3.0, 4.0}};
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, v, out)), 4.0);
}

TEST_F(TransferTest, NumelOnlyFiresWhenInputFires) {
    long src = net->add_node({},    Operation::nop,   false);
    long out = net->add_node({src}, Operation::numel, false);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
    post_get(src, signals::Value{1.0}, out);
    EXPECT_TRUE(signals::has_value(net->get_current_value(out)));
}

// ── function_op (0) ───────────────────────────────────────────────────────────

TEST_F(TransferTest, FunctionOpMap) {
    long src = net->add_node({},    Operation::nop,      false);
    long out = net->add_node({src}, Operation::function, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) * 2.0}, true};
        });

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{6.0}, out)), 12.0);
}

TEST_F(TransferTest, FunctionOpMapn) {
    long a   = net->add_node({},     Operation::nop,      false);
    long b   = net->add_node({},     Operation::nop,      false);
    long out = net->add_node({a, b}, Operation::function, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) + std::get<double>(ins[1])}, true};
        });

    post(a, signals::Value{3.0});
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{4.0}, out)), 7.0);
}

TEST_F(TransferTest, FunctionOpScanAccumulates) {
    long item = net->add_node({},     Operation::nop,      false);
    long out  = net->add_node({item}, Operation::function, false,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc, long)
            -> std::pair<signals::Value, bool>
        {
            const double prev = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return {signals::Value{prev + std::get<double>(ins[0])}, true};
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
    long out = net->add_node({src}, Operation::function, false,
        [](const std::vector<signals::Value>&, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{}, false};
        });

    post_get(src, signals::Value{1.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── map_op (60) ───────────────────────────────────────────────────────────────

TEST_F(TransferTest, MapOpAppliesCallable) {
    long src = net->add_node({},    Operation::nop,    false);
    long out = net->add_node({src}, Operation::map_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) * 3.0}, true};
        });

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{4.0}, out)), 12.0);
}

TEST_F(TransferTest, MapOpSamplesInput1WithoutCallable) {
    long trigger = net->add_node({},              Operation::nop,    false);
    long val     = net->add_node({},              Operation::nop,    false);
    long out     = net->add_node({trigger, val},  Operation::map_op, false);
    // No callable: samples val when trigger fires.

    post(val, signals::Value{99.0});
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(trigger, signals::Value{0.0}, out)), 99.0);
}

TEST_F(TransferTest, MapOpOnlyFiresWhenInput0HasNewValue) {
    long trigger = net->add_node({},              Operation::nop,    false);
    long val     = net->add_node({},              Operation::nop,    false);
    long out     = net->add_node({trigger, val},  Operation::map_op, false);

    post(trigger, signals::Value{0.0});
    post(val, signals::Value{5.0}); // val fires but trigger doesn't → no update
    // out fires when trigger fires (which set val's value), but here trigger was
    // first and val wasn't set yet → out is still empty
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── mapn_op (61) ──────────────────────────────────────────────────────────────

TEST_F(TransferTest, MapnOpRequiresAllInputsSeeded) {
    long a   = net->add_node({},     Operation::nop,     false);
    long b   = net->add_node({},     Operation::nop,     false);
    long out = net->add_node({a, b}, Operation::mapn_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) + std::get<double>(ins[1])}, true};
        });

    post(a, signals::Value{3.0});
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{4.0}, out)), 7.0);
}

TEST_F(TransferTest, MapnOpFiresWhenEitherUpdatesAfterSeeded) {
    long a   = net->add_node({},     Operation::nop,     false);
    long b   = net->add_node({},     Operation::nop,     false);
    long out = net->add_node({a, b}, Operation::mapn_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) * std::get<double>(ins[1])}, true};
        });

    post(a, signals::Value{2.0});
    post(b, signals::Value{3.0});
    // a fires again → uses latest b (3) → 5 * 3 = 15
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{5.0}, out)), 15.0);
}

// ── filter_op (62) ────────────────────────────────────────────────────────────

TEST_F(TransferTest, FilterOpPassesThroughWhenTruthy) {
    long src = net->add_node({},    Operation::nop,       false);
    long out = net->add_node({src}, Operation::filter_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) > 0.0}, true};
        });

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(src, signals::Value{5.0}, out)), 5.0);
}

TEST_F(TransferTest, FilterOpSuppressesWhenFalsy) {
    long src = net->add_node({},    Operation::nop,       false);
    long out = net->add_node({src}, Operation::filter_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) > 0.0}, true};
        });

    post_get(src, signals::Value{-1.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

TEST_F(TransferTest, FilterOpOnlyFiresWhenInput0HasNewValue) {
    long src = net->add_node({},    Operation::nop,       false);
    long out = net->add_node({src}, Operation::filter_op, false,
        [](const std::vector<signals::Value>&, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        { return {signals::Value{true}, true}; });

    // No fire before src updates
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
    post_get(src, signals::Value{1.0}, out);
    EXPECT_TRUE(signals::has_value(net->get_current_value(out)));
}

// ── scan_op (63) ──────────────────────────────────────────────────────────────

TEST_F(TransferTest, ScanOpSeedAloneOutputsSeedDirectly) {
    long item = net->add_node({},            Operation::nop,     false);
    long seed = net->add_node({},            Operation::nop,     false);
    long out  = net->add_node({item, seed},  Operation::scan_op, false,
        // callable should NOT be called when seed fires alone
        [](const std::vector<signals::Value>&, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        { return {signals::Value{999.0}, true}; });

    // Seed fires alone → output = seed value (NOT through callable)
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(seed, signals::Value{10.0}, out)), 10.0);
}

TEST_F(TransferTest, ScanOpFoldsItems) {
    long item = net->add_node({},           Operation::nop,     false);
    long seed = net->add_node({},           Operation::nop,     false);
    long out  = net->add_node({item, seed}, Operation::scan_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc, long)
            -> std::pair<signals::Value, bool>
        {
            double prev = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return {signals::Value{prev + std::get<double>(ins[0])}, true};
        });

    post(seed, signals::Value{0.0});     // initialise accumulator to 0
    post_get(item, signals::Value{1.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 1.0);
    post_get(item, signals::Value{2.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 3.0);
}

TEST_F(TransferTest, ScanOpSeedResetsAccumulator) {
    long item = net->add_node({},           Operation::nop,     false);
    long seed = net->add_node({},           Operation::nop,     false);
    long out  = net->add_node({item, seed}, Operation::scan_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc, long)
            -> std::pair<signals::Value, bool>
        {
            double prev = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return {signals::Value{prev + std::get<double>(ins[0])}, true};
        });

    post(seed, signals::Value{0.0});
    post_get(item, signals::Value{5.0}, out);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 5.0);

    // Seed fires alone → direct output = new seed value (accumulator reset)
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(seed, signals::Value{100.0}, out)), 100.0);
}

TEST_F(TransferTest, ScanOpSeedAndItemSameTick) {
    long item = net->add_node({},           Operation::nop,     false);
    long seed = net->add_node({},           Operation::nop,     false);
    long out  = net->add_node({item, seed}, Operation::scan_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc, long)
            -> std::pair<signals::Value, bool>
        {
            double init = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return {signals::Value{init + std::get<double>(ins[0])}, true};
        });

    // Both transact before apply: seed fires first (alone case sets 10),
    // then item fires with seed still in working state → acc=10, item=5 → 15
    auto aff_seed = net->transact(seed, signals::Value{10.0});
    auto aff_item = net->transact(item, signals::Value{5.0});
    std::vector<long> all;
    all.insert(all.end(), aff_seed.begin(), aff_seed.end());
    all.insert(all.end(), aff_item.begin(), aff_item.end());
    net->apply(all);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(out)), 15.0);
}

TEST_F(TransferTest, ScanOpNoOutputBeforeSeedHasValue) {
    long item = net->add_node({},           Operation::nop,     false);
    long seed = net->add_node({},           Operation::nop,     false);
    long out  = net->add_node({item, seed}, Operation::scan_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value& acc, long)
            -> std::pair<signals::Value, bool>
        {
            double init = signals::has_value(acc) ? std::get<double>(acc) : 0.0;
            return {signals::Value{init + std::get<double>(ins[0])}, true};
        });

    // Item fires but seed has never provided a value → suppressed
    post_get(item, signals::Value{5.0}, out);
    EXPECT_FALSE(signals::has_value(net->get_current_value(out)));
}

// ── flatten_op (41) ───────────────────────────────────────────────────────────

TEST_F(TransferTest, FlattenOpDirectorCallableReturnsValue) {
    long director = net->add_node({},         Operation::nop,        false);
    long flat     = net->add_node({director}, Operation::flatten_op, false,
        [](const std::vector<signals::Value>& ins, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            return {signals::Value{std::get<double>(ins[0]) * 2.0}, true};
        });

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(director, signals::Value{5.0}, flat)), 10.0);
}

TEST_F(TransferTest, FlattenOpSourcePassthrough) {
    // inputs[1] fires → pure C++ passthrough with no callable needed.
    long director = net->add_node({},               Operation::nop,        false);
    long source   = net->add_node({},               Operation::nop,        false);
    long flat     = net->add_node({director, source}, Operation::flatten_op, false);

    EXPECT_DOUBLE_EQ(std::get<double>(post_get(source, signals::Value{7.0}, flat)), 7.0);
}

TEST_F(TransferTest, FlattenOpDirectorNoCallableNoOutput) {
    long director = net->add_node({},         Operation::nop,        false);
    long flat     = net->add_node({director}, Operation::flatten_op, false);

    post_get(director, signals::Value{5.0}, flat);
    EXPECT_FALSE(signals::has_value(net->get_current_value(flat)));
}

TEST_F(TransferTest, FlattenOpCallableRewiresToSource) {
    long director = net->add_node({}, Operation::nop, false);
    long source   = net->add_node({}, Operation::nop, false);

    long flat = net->add_node({director}, Operation::flatten_op, false,
        [this, director, source]
        (const std::vector<signals::Value>&, const signals::Value&, long node_id)
            -> std::pair<signals::Value, bool>
        {
            net->set_node_inputs(node_id, {director, source});
            auto v = net->get_latest_value(source);
            return signals::has_value(v)
                ? std::make_pair(v,                  true)
                : std::make_pair(signals::Value{}, false);
        });

    post(source, signals::Value{42.0});

    // Director fires → callable rewires, source has value → output 42
    post_get(director, signals::Value{0.0}, flat);
    EXPECT_DOUBLE_EQ(std::get<double>(net->get_current_value(flat)), 42.0);

    // Source fires → pure passthrough
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(source, signals::Value{99.0}, flat)), 99.0);
}

// ── flatten_struct_op (40) ────────────────────────────────────────────────────

TEST_F(TransferTest, FlattenStructOpCallableInvokedOnAnyInput) {
    long blueprint = net->add_node({}, Operation::nop, false);
    long field     = net->add_node({}, Operation::nop, false);
    int  calls     = 0;

    long fs = net->add_node({blueprint, field}, Operation::flatten_struct_op, false,
        [&calls](const std::vector<signals::Value>&, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        {
            ++calls;
            return {signals::Value{1.0}, true};
        });

    EXPECT_EQ(calls, 0);
    post_get(blueprint, signals::Value{1.0}, fs);
    EXPECT_EQ(calls, 1);
    post_get(field, signals::Value{2.0}, fs);
    EXPECT_EQ(calls, 2);
}

TEST_F(TransferTest, FlattenStructOpSuppressedWhenCallableReturnsFalse) {
    long bp = net->add_node({},   Operation::nop,               false);
    long fs = net->add_node({bp}, Operation::flatten_struct_op, false,
        [](const std::vector<signals::Value>&, const signals::Value&, long)
            -> std::pair<signals::Value, bool>
        { return {signals::Value{}, false}; });

    post_get(bp, signals::Value{1.0}, fs);
    EXPECT_FALSE(signals::has_value(net->get_current_value(fs)));
}

// ── set_node_inputs ───────────────────────────────────────────────────────────

TEST_F(TransferTest, SetNodeInputsRewiresTargetship) {
    long a   = net->add_node({},  Operation::nop,      false);
    long b   = net->add_node({},  Operation::nop,      false);
    long out = net->add_node({a}, Operation::identity, false);

    // Initially follows a.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(a, signals::Value{1.0}, out)), 1.0);

    // Rewire to b.
    EXPECT_TRUE(net->set_node_inputs(out, {b}));

    // a fires — out is no longer in a's targets.
    auto aff = net->transact(a, signals::Value{99.0});
    net->apply(aff);
    EXPECT_EQ(std::find(aff.begin(), aff.end(), out), aff.end());

    // b fires — out follows b now.
    EXPECT_DOUBLE_EQ(std::get<double>(post_get(b, signals::Value{2.0}, out)), 2.0);
}

TEST_F(TransferTest, SetNodeInputsToEmptyDisconnects) {
    long a   = net->add_node({},  Operation::nop,      false);
    long out = net->add_node({a}, Operation::identity, false);

    EXPECT_TRUE(net->set_node_inputs(out, {}));

    auto aff = net->transact(a, signals::Value{5.0});
    net->apply(aff);
    EXPECT_EQ(std::find(aff.begin(), aff.end(), out), aff.end());
}

TEST_F(TransferTest, SetNodeInputsInvalidNodeReturnsFalse) {
    EXPECT_FALSE(net->set_node_inputs(9999, {0}));
}

// ── appendValues ─────────────────────────────────────────────────────────────

TEST_F(TransferTest, AppendValuesAccumulatesScalars) {
    long src = net->add_node({},    Operation::nop,      false);
    long acc = net->add_node({src}, Operation::identity, true); // appendValues=true

    post_get(src, signals::Value{1.0}, acc);
    post_get(src, signals::Value{2.0}, acc);
    post_get(src, signals::Value{3.0}, acc);

    auto result = net->get_current_value(acc);
    ASSERT_TRUE(std::holds_alternative<std::vector<double>>(result));
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

    auto result = net->get_current_value(acc);
    ASSERT_TRUE(std::holds_alternative<std::vector<double>>(result));
    const auto& v = std::get<std::vector<double>>(result);
    ASSERT_EQ(v.size(), 4u);
    EXPECT_DOUBLE_EQ(v[2], 3.0);
    EXPECT_DOUBLE_EQ(v[3], 4.0);
}

// ── is_truthy ─────────────────────────────────────────────────────────────────

TEST(TestValueHelpers, IsTruthy) {
    EXPECT_FALSE(signals::is_truthy(signals::Value{}));
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
    EXPECT_FALSE(signals::values_equal(signals::Value{1.0}, signals::Value{true}));
}
