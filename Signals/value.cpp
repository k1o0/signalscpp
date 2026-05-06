// value.cpp — implementation of signals::Value operations.
// Core layer: no mex.h, <Python.h>, or pybind11 headers here.

#include "value.h"
#include <string>

namespace signals {

// ── type_name ─────────────────────────────────────────────────────────────────

const char* type_name(const Value& v) noexcept {
    return std::visit([](const auto& x) noexcept -> const char* {
        using T = std::decay_t<decltype(x)>;
        if constexpr (std::is_same_v<T, std::monostate>)           return "monostate";
        else if constexpr (std::is_same_v<T, double>)              return "double";
        else if constexpr (std::is_same_v<T, bool>)                return "bool";
        else if constexpr (std::is_same_v<T, std::string>)         return "string";
        else if constexpr (std::is_same_v<T, std::vector<double>>) return "vector<double>";
        else                                                        return "unknown";
    }, v);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

namespace {

[[noreturn]] void throw_type_error(const char* op, const Value& a, const Value& b) {
    throw TypeError(std::string(op) + ": unsupported operand types '"
                    + type_name(a) + "' and '" + type_name(b) + "'");
}

// Applies a binary double→double op element-wise across the supported numeric
// value combinations: scalar*scalar, vec*vec (same size), and scalar broadcasts.
// Returns double for scalar*scalar, vector<double> otherwise.
template<typename Op>
Value numeric_binop(const Value& a, const Value& b, Op op, const char* name) {
    const bool a_scalar = std::holds_alternative<double>(a);
    const bool b_scalar = std::holds_alternative<double>(b);
    const bool a_vec    = std::holds_alternative<std::vector<double>>(a);
    const bool b_vec    = std::holds_alternative<std::vector<double>>(b);

    if (a_scalar && b_scalar)
        return op(std::get<double>(a), std::get<double>(b));

    if (a_vec && b_vec) {
        const auto& va = std::get<std::vector<double>>(a);
        const auto& vb = std::get<std::vector<double>>(b);
        if (va.size() != vb.size())
            throw TypeError(std::string(name) + ": vector sizes don't match ("
                            + std::to_string(va.size()) + " vs "
                            + std::to_string(vb.size()) + ")");
        std::vector<double> result(va.size());
        for (size_t i = 0; i < va.size(); ++i)
            result[i] = op(va[i], vb[i]);
        return result;
    }

    if (a_scalar && b_vec) {
        const double s = std::get<double>(a);
        const auto& vb = std::get<std::vector<double>>(b);
        std::vector<double> result(vb.size());
        for (size_t i = 0; i < vb.size(); ++i)
            result[i] = op(s, vb[i]);
        return result;
    }

    if (a_vec && b_scalar) {
        const auto& va = std::get<std::vector<double>>(a);
        const double s = std::get<double>(b);
        std::vector<double> result(va.size());
        for (size_t i = 0; i < va.size(); ++i)
            result[i] = op(va[i], s);
        return result;
    }

    throw_type_error(name, a, b);
}

// Ordered comparison for double and vector<double>.
// Scalar-scalar → bool.  Vec-vec → vector<double> (0.0 = false, 1.0 = true).
template<typename Cmp>
Value ordered_cmp(const Value& a, const Value& b, Cmp cmp, const char* name) {
    if (std::holds_alternative<double>(a) && std::holds_alternative<double>(b))
        return cmp(std::get<double>(a), std::get<double>(b));

    if (std::holds_alternative<std::vector<double>>(a) &&
        std::holds_alternative<std::vector<double>>(b)) {
        const auto& va = std::get<std::vector<double>>(a);
        const auto& vb = std::get<std::vector<double>>(b);
        if (va.size() != vb.size())
            throw TypeError(std::string(name) + ": vector sizes don't match ("
                            + std::to_string(va.size()) + " vs "
                            + std::to_string(vb.size()) + ")");
        std::vector<double> result(va.size());
        for (size_t i = 0; i < va.size(); ++i)
            result[i] = cmp(va[i], vb[i]) ? 1.0 : 0.0;
        return result;
    }

    throw_type_error(name, a, b);
}

} // anonymous namespace

// ── Arithmetic ────────────────────────────────────────────────────────────────

// legacy: addNode transferer op `plus`
Value add(const Value& a, const Value& b) {
    return numeric_binop(a, b, [](double x, double y) { return x + y; }, "add");
}

// legacy: transferer op `minus`
Value subtract(const Value& a, const Value& b) {
    return numeric_binop(a, b, [](double x, double y) { return x - y; }, "subtract");
}

// legacy: transferer op `mtimes`
Value multiply(const Value& a, const Value& b) {
    return numeric_binop(a, b, [](double x, double y) { return x * y; }, "multiply");
}

// legacy: transferer op `rdivide`  (a ./ b)
Value rdivide(const Value& a, const Value& b) {
    return numeric_binop(a, b, [](double x, double y) { return x / y; }, "rdivide");
}

// legacy: transferer op `mdivide`  (a .\ b == b ./ a)
Value ldivide(const Value& a, const Value& b) {
    return numeric_binop(a, b, [](double x, double y) { return y / x; }, "ldivide");
}

// ── Comparison ────────────────────────────────────────────────────────────────

// legacy: transferer op `gt`
Value gt(const Value& a, const Value& b) {
    return ordered_cmp(a, b, [](double x, double y) { return x > y; }, "gt");
}

// legacy: transferer op `ge`
Value ge(const Value& a, const Value& b) {
    return ordered_cmp(a, b, [](double x, double y) { return x >= y; }, "ge");
}

// legacy: transferer op `lt`
Value lt(const Value& a, const Value& b) {
    return ordered_cmp(a, b, [](double x, double y) { return x < y; }, "lt");
}

// legacy: transferer op `le`
Value le(const Value& a, const Value& b) {
    return ordered_cmp(a, b, [](double x, double y) { return x <= y; }, "le");
}

// legacy: transferer op `eq`
// Extends ordered_cmp with bool==bool and string==string support.
Value eq(const Value& a, const Value& b) {
    if (std::holds_alternative<bool>(a) && std::holds_alternative<bool>(b))
        return std::get<bool>(a) == std::get<bool>(b);
    if (std::holds_alternative<std::string>(a) && std::holds_alternative<std::string>(b))
        return std::get<std::string>(a) == std::get<std::string>(b);
    return ordered_cmp(a, b, [](double x, double y) { return x == y; }, "eq");
}

} // namespace signals
