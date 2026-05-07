#pragma once
#ifndef SIGNALS_VALUE_H
#define SIGNALS_VALUE_H

#include <variant>
#include <string>
#include <vector>
#include <stdexcept>

#if defined(SIGNALS_STATIC_LIB)
#define SIGNALS_API
#elif defined(SIGNALS_EXPORTS)
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

// ── signals::Value ────────────────────────────────────────────────────────────
//
// Replaces the `DataContainer` / `mxArray*` approach from the legacy C MEX
// backend.  The set of supported alternatives is intentionally small and
// fixed — extend it deliberately, and update the MEX and Python boundary
// converters (fromMx/toMx, fromPy/toPy) whenever you do.
//
// Cross-cutting rules enforced here:
//   • No silent coercion between alternatives.  Type mismatches throw
//     signals::TypeError.
//   • The core never depends on mex.h, <Python.h>, or pybind11 headers.
//     If you are tempted to include one of those here, you are in the wrong
//     layer — move the code to the binding layer.
//   • Operations are implemented with std::visit; do not switch on
//     index() directly.

namespace signals {

// ── Error hierarchy ───────────────────────────────────────────────────────────
// legacy analogue: mexErrMsgIdAndTxt / C return-codes in network.c.
// The MEX binding layer catches signals::Error and calls mexErrMsgIdAndTxt.
// The Python binding layer lets pybind11 translate to a Python exception.

class Error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// Thrown when an operation is called with operand types it does not support.
// There is no silent coercion in the core — this must be raised explicitly.
class TypeError : public Error {
public:
    using Error::Error;
};

// ── Value type ────────────────────────────────────────────────────────────────
// legacy: mxArray* (MATLAB's dynamically-typed value container)
//
// Alternative mapping:
//   std::monostate          → node not yet fired  (legacy: "no current value")
//   double                  → MATLAB double scalar (most common numeric type)
//   bool                    → MATLAB logical scalar
//   std::string             → MATLAB char/string, stored as UTF-8 in the core
//   std::vector<double>     → 1-D numeric array, row-major in core
//                             (MATLAB is column-major; MEX layer converts)
//
// Future extension (zero-copy NumPy/mxArray views): add a non-owning span
// alternative plus a type-erased keepalive holding the source-language
// reference.  Extend the variant — do not replace the architecture.
// Do not pre-empt this; wait for a real use case.
using Value = std::variant<
    std::monostate,         // "no value yet"
    double,                 // MATLAB's default numeric type
    bool,
    std::string,            // UTF-8; bindings convert at the boundary
    std::vector<double>     // 1-D array, row-major
>;

// ── Helpers ───────────────────────────────────────────────────────────────────

// Returns false only when the Value holds std::monostate ("not yet fired").
[[nodiscard]] inline bool has_value(const Value& v) noexcept {
    return !std::holds_alternative<std::monostate>(v);
}

// Returns true when the value is "truthy" in the MATLAB / Python sense:
//   bool: true
//   double: non-zero
//   vector<double>: non-empty and at least one non-zero element
//   string: non-empty
//   monostate: false
[[nodiscard]] inline bool is_truthy(const Value& v) noexcept {
    return std::visit([](const auto& x) -> bool {
        using T = std::decay_t<decltype(x)>;
        if constexpr (std::is_same_v<T, std::monostate>)        return false;
        if constexpr (std::is_same_v<T, bool>)                  return x;
        if constexpr (std::is_same_v<T, double>)                return x != 0.0;
        if constexpr (std::is_same_v<T, std::string>)           return !x.empty();
        if constexpr (std::is_same_v<T, std::vector<double>>)   {
            for (double d : x) if (d != 0.0) return true;
            return false;
        }
    }, v);
}

// Returns true when two Values are equal in every element (mirrors MATLAB isequal).
// monostate == monostate is true; monostate != anything else.
[[nodiscard]] SIGNALS_API bool values_equal(const Value& a, const Value& b) noexcept;

// Returns a human-readable name for the active alternative.
// Return value is a static string — do not free it.
[[nodiscard]] SIGNALS_API const char* type_name(const Value& v) noexcept;

// ── Arithmetic operations ─────────────────────────────────────────────────────
// Legacy ops: plus / minus / mtimes / rdivide / mdivide  (transferer.h)
//
// Supported operand combinations:
//   double       OP double                → double
//   vector<double> OP vector<double>      → vector<double>  (element-wise)
//   double       OP vector<double>        → vector<double>  (scalar broadcast)
//   vector<double> OP double              → vector<double>  (scalar broadcast)
//
// All other combinations throw TypeError.

[[nodiscard]] SIGNALS_API Value add(const Value& a, const Value& b);       // legacy: plus
[[nodiscard]] SIGNALS_API Value subtract(const Value& a, const Value& b);  // legacy: minus
[[nodiscard]] SIGNALS_API Value multiply(const Value& a, const Value& b);  // legacy: mtimes
[[nodiscard]] SIGNALS_API Value rdivide(const Value& a, const Value& b);   // legacy: rdivide  (a ./ b)
[[nodiscard]] SIGNALS_API Value ldivide(const Value& a, const Value& b);   // legacy: mdivide  (a .\ b == b ./ a)

// ── Comparison operations ─────────────────────────────────────────────────────
// Legacy ops: gt / ge / lt / le / eq  (transferer.h)
//
// For ordered comparisons (gt/ge/lt/le):
//   double       CMP double               → bool
//   vector<double> CMP vector<double>     → vector<double>  (0.0=false, 1.0=true)
//
// For equality (eq), additionally:
//   bool         == bool                  → bool
//   string       == string                → bool
//
// All other combinations throw TypeError.

[[nodiscard]] SIGNALS_API Value gt(const Value& a, const Value& b);
[[nodiscard]] SIGNALS_API Value ge(const Value& a, const Value& b);
[[nodiscard]] SIGNALS_API Value lt(const Value& a, const Value& b);
[[nodiscard]] SIGNALS_API Value le(const Value& a, const Value& b);
[[nodiscard]] SIGNALS_API Value eq(const Value& a, const Value& b);

} // namespace signals

#endif // SIGNALS_VALUE_H
