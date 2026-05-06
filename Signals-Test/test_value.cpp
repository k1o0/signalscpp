#include "pch.h"
#include <gtest/gtest.h>
#include "../Signals/value.h"

// ── has_value / type_name ─────────────────────────────────────────────────────

TEST(TestValue, HasValue) {
    EXPECT_FALSE(signals::has_value(signals::Value{}));
    EXPECT_TRUE(signals::has_value(signals::Value{ 1.0 }));
    EXPECT_TRUE(signals::has_value(signals::Value{ true }));
    EXPECT_TRUE(signals::has_value(signals::Value{ std::string("hi") }));
    EXPECT_TRUE(signals::has_value(signals::Value{ std::vector<double>{1.0, 2.0} }));
}

TEST(TestValue, TypeName) {
    EXPECT_STREQ(signals::type_name(signals::Value{}),                         "monostate");
    EXPECT_STREQ(signals::type_name(signals::Value{ 1.0 }),                    "double");
    EXPECT_STREQ(signals::type_name(signals::Value{ true }),                   "bool");
    EXPECT_STREQ(signals::type_name(signals::Value{ std::string("x") }),       "string");
    EXPECT_STREQ(signals::type_name(signals::Value{ std::vector<double>{} }),  "vector<double>");
}

// ── Arithmetic ────────────────────────────────────────────────────────────────

TEST(TestValueArith, AddScalars) {
    auto r = signals::add(signals::Value{ 3.0 }, signals::Value{ 4.0 });
    EXPECT_DOUBLE_EQ(std::get<double>(r), 7.0);
}

TEST(TestValueArith, SubtractScalars) {
    auto r = signals::subtract(signals::Value{ 10.0 }, signals::Value{ 3.0 });
    EXPECT_DOUBLE_EQ(std::get<double>(r), 7.0);
}

TEST(TestValueArith, MultiplyScalars) {
    auto r = signals::multiply(signals::Value{ 3.0 }, signals::Value{ 4.0 });
    EXPECT_DOUBLE_EQ(std::get<double>(r), 12.0);
}

TEST(TestValueArith, RdivideScalars) {
    auto r = signals::rdivide(signals::Value{ 10.0 }, signals::Value{ 4.0 });
    EXPECT_DOUBLE_EQ(std::get<double>(r), 2.5);
}

TEST(TestValueArith, LdivideScalars) {
    // a .\ b == b ./ a
    auto r = signals::ldivide(signals::Value{ 4.0 }, signals::Value{ 10.0 });
    EXPECT_DOUBLE_EQ(std::get<double>(r), 2.5);
}

TEST(TestValueArith, AddVectors) {
    signals::Value a{ std::vector<double>{1.0, 2.0, 3.0} };
    signals::Value b{ std::vector<double>{4.0, 5.0, 6.0} };
    auto r = signals::add(a, b);
    auto& rv = std::get<std::vector<double>>(r);
    ASSERT_EQ(rv.size(), 3u);
    EXPECT_DOUBLE_EQ(rv[0], 5.0);
    EXPECT_DOUBLE_EQ(rv[1], 7.0);
    EXPECT_DOUBLE_EQ(rv[2], 9.0);
}

TEST(TestValueArith, ScalarBroadcastLeft) {
    signals::Value scalar{ 2.0 };
    signals::Value vec{ std::vector<double>{1.0, 2.0, 3.0} };
    auto r = signals::multiply(scalar, vec);
    auto& rv = std::get<std::vector<double>>(r);
    ASSERT_EQ(rv.size(), 3u);
    EXPECT_DOUBLE_EQ(rv[0], 2.0);
    EXPECT_DOUBLE_EQ(rv[1], 4.0);
    EXPECT_DOUBLE_EQ(rv[2], 6.0);
}

TEST(TestValueArith, ScalarBroadcastRight) {
    signals::Value vec{ std::vector<double>{1.0, 2.0, 3.0} };
    signals::Value scalar{ 10.0 };
    auto r = signals::add(vec, scalar);
    auto& rv = std::get<std::vector<double>>(r);
    EXPECT_DOUBLE_EQ(rv[0], 11.0);
    EXPECT_DOUBLE_EQ(rv[1], 12.0);
    EXPECT_DOUBLE_EQ(rv[2], 13.0);
}

TEST(TestValueArith, VectorSizeMismatchThrows) {
    signals::Value a{ std::vector<double>{1.0, 2.0} };
    signals::Value b{ std::vector<double>{1.0, 2.0, 3.0} };
    EXPECT_THROW(signals::add(a, b), signals::TypeError);
}

TEST(TestValueArith, TypeMismatchThrows) {
    EXPECT_THROW(signals::add(signals::Value{ 1.0 }, signals::Value{ true }),        signals::TypeError);
    EXPECT_THROW(signals::add(signals::Value{ std::string("a") }, signals::Value{ 1.0 }), signals::TypeError);
    EXPECT_THROW(signals::add(signals::Value{}, signals::Value{ 1.0 }),              signals::TypeError);
}

// ── Comparison ────────────────────────────────────────────────────────────────

TEST(TestValueCmp, GtScalar) {
    EXPECT_TRUE(std::get<bool>(signals::gt(signals::Value{ 5.0 }, signals::Value{ 3.0 })));
    EXPECT_FALSE(std::get<bool>(signals::gt(signals::Value{ 3.0 }, signals::Value{ 5.0 })));
    EXPECT_FALSE(std::get<bool>(signals::gt(signals::Value{ 3.0 }, signals::Value{ 3.0 })));
}

TEST(TestValueCmp, GeScalar) {
    EXPECT_TRUE(std::get<bool>(signals::ge(signals::Value{ 3.0 }, signals::Value{ 3.0 })));
    EXPECT_TRUE(std::get<bool>(signals::ge(signals::Value{ 4.0 }, signals::Value{ 3.0 })));
    EXPECT_FALSE(std::get<bool>(signals::ge(signals::Value{ 2.0 }, signals::Value{ 3.0 })));
}

TEST(TestValueCmp, LtScalar) {
    EXPECT_TRUE(std::get<bool>(signals::lt(signals::Value{ 2.0 }, signals::Value{ 5.0 })));
    EXPECT_FALSE(std::get<bool>(signals::lt(signals::Value{ 5.0 }, signals::Value{ 2.0 })));
}

TEST(TestValueCmp, LeScalar) {
    EXPECT_TRUE(std::get<bool>(signals::le(signals::Value{ 3.0 }, signals::Value{ 3.0 })));
    EXPECT_FALSE(std::get<bool>(signals::le(signals::Value{ 4.0 }, signals::Value{ 3.0 })));
}

TEST(TestValueCmp, EqScalar) {
    EXPECT_TRUE(std::get<bool>(signals::eq(signals::Value{ 3.0 }, signals::Value{ 3.0 })));
    EXPECT_FALSE(std::get<bool>(signals::eq(signals::Value{ 3.0 }, signals::Value{ 4.0 })));
}

TEST(TestValueCmp, EqBool) {
    EXPECT_TRUE(std::get<bool>(signals::eq(signals::Value{ true },  signals::Value{ true })));
    EXPECT_TRUE(std::get<bool>(signals::eq(signals::Value{ false }, signals::Value{ false })));
    EXPECT_FALSE(std::get<bool>(signals::eq(signals::Value{ true }, signals::Value{ false })));
}

TEST(TestValueCmp, EqString) {
    EXPECT_TRUE(std::get<bool>(signals::eq(
        signals::Value{ std::string("hello") },
        signals::Value{ std::string("hello") })));
    EXPECT_FALSE(std::get<bool>(signals::eq(
        signals::Value{ std::string("hello") },
        signals::Value{ std::string("world") })));
}

TEST(TestValueCmp, VectorCmp) {
    signals::Value a{ std::vector<double>{1.0, 5.0, 3.0} };
    signals::Value b{ std::vector<double>{2.0, 4.0, 3.0} };
    auto r = signals::gt(a, b);
    auto& rv = std::get<std::vector<double>>(r);
    ASSERT_EQ(rv.size(), 3u);
    EXPECT_DOUBLE_EQ(rv[0], 0.0);  // 1 > 2 = false
    EXPECT_DOUBLE_EQ(rv[1], 1.0);  // 5 > 4 = true
    EXPECT_DOUBLE_EQ(rv[2], 0.0);  // 3 > 3 = false
}

TEST(TestValueCmp, OrderedCmpTypeMismatchThrows) {
    EXPECT_THROW(signals::gt(signals::Value{ 1.0 }, signals::Value{ true }),    signals::TypeError);
    EXPECT_THROW(signals::lt(signals::Value{ std::string("a") }, signals::Value{ 1.0 }), signals::TypeError);
}
