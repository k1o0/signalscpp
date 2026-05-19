#pragma once
#ifndef SIGNALS_VALUE_TRAITS_H
#define SIGNALS_VALUE_TRAITS_H

#include "value.h"
#include <cstddef>
#include <optional>

// ---------------------------------------------------------------------------
// ValueTraits<V> — per-binding policy for value operations.
//
// Each binding layer specialises this template for its native value type.
// NetworkT<V> and network_impl.h use only these static members and never
// include binding-specific headers.
//
// REQUIRED members (every specialisation must define):
//   has_value(v)         — true iff v is not the "no-value" sentinel
//   is_truthy(v)         — truthiness for gate opcodes (keepWhen, at_op, ...)
//   values_equal(a, b)   — equality for skip_repeats
//   no_value()           — return the sentinel for "node not yet fired"
//   from_bool(b)         — wrap a bool as V (latch output)
//   from_double(d)       — wrap a double scalar as V (numel output)
//   numel(v)             — number of elements as double
//   append(current, wv)  — concat wv onto current (buffer/bufferUpTo nodes)
//   to_index(v)          — convert V to a 0-based size_t index, or nullopt
//
// OPTIONAL arithmetic / comparison (default: throw signals::TypeError).
// Bindings can override incrementally as C++ implementations become available.
// ---------------------------------------------------------------------------

template <typename V>
struct ValueTraits {
    // Required — no default body (a missing specialisation will not link).
    static bool                  has_value   (const V&);
    static bool                  is_truthy   (const V&);
    static bool                  values_equal(const V&, const V&);
    static V                     no_value    ();
    static V                     from_bool   (bool);
    static V                     from_double (double);
    static double                numel       (const V&);
    static V                     append      (const V& current, const V& working);
    static std::optional<size_t> to_index    (const V&);

    // Arithmetic / comparison — throw by default so bindings opt in incrementally.
    static V add     (const V&, const V&) { throw signals::TypeError("add not implemented for this value type");      }
    static V subtract(const V&, const V&) { throw signals::TypeError("subtract not implemented for this value type"); }
    static V multiply(const V&, const V&) { throw signals::TypeError("multiply not implemented for this value type"); }
    static V rdivide (const V&, const V&) { throw signals::TypeError("rdivide not implemented for this value type");  }
    static V ldivide (const V&, const V&) { throw signals::TypeError("ldivide not implemented for this value type");  }
    static V gt(const V&, const V&)       { throw signals::TypeError("gt not implemented for this value type"); }
    static V ge(const V&, const V&)       { throw signals::TypeError("ge not implemented for this value type"); }
    static V lt(const V&, const V&)       { throw signals::TypeError("lt not implemented for this value type"); }
    static V le(const V&, const V&)       { throw signals::TypeError("le not implemented for this value type"); }
    static V eq(const V&, const V&)       { throw signals::TypeError("eq not implemented for this value type"); }

    // buffer_up_to — throw by default; specialisations provide typed implementations.
    // cast_on_type_change: if true, silently promote to cell/variant type on mismatch;
    //                      if false (default), throw TypeError on type change.
    static V buffer_up_to(const V&, const V&, size_t, bool = false) {
        throw signals::TypeError("buffer_up_to not implemented for this value type");
    }
};

// ---------------------------------------------------------------------------
// signals::Value specialisation — wraps the free functions in value.h
// ---------------------------------------------------------------------------
template <>
struct ValueTraits<signals::Value> {
    static bool has_value   (const signals::Value& v) noexcept { return signals::has_value(v);        }
    static bool is_truthy   (const signals::Value& v) noexcept { return signals::is_truthy(v);        }
    static bool values_equal(const signals::Value& a,
                              const signals::Value& b) noexcept { return signals::values_equal(a, b); }
    static signals::Value no_value() noexcept { return {}; }

    static signals::Value from_bool  (bool b)   noexcept { return b; }
    static signals::Value from_double(double d) noexcept { return d; }

    static double numel(const signals::Value& v) noexcept {
        return std::visit([](const auto& x) -> double {
            using T = std::decay_t<decltype(x)>;
            if constexpr (std::is_same_v<T, std::vector<double>>) return static_cast<double>(x.size());
            else if constexpr (std::is_same_v<T, std::monostate>) return 0.0;
            else                                                    return 1.0;
        }, v);
    }

    static signals::Value append(const signals::Value& current, const signals::Value& working) {
        std::vector<double> acc;
        if (std::holds_alternative<std::vector<double>>(current))
            acc = std::get<std::vector<double>>(current);
        std::visit([&acc](const auto& wv) {
            using T = std::decay_t<decltype(wv)>;
            if constexpr (std::is_same_v<T, double>)
                acc.push_back(wv);
            else if constexpr (std::is_same_v<T, std::vector<double>>)
                acc.insert(acc.end(), wv.begin(), wv.end());
        }, working);
        return acc;
    }

    static std::optional<size_t> to_index(const signals::Value& v) {
        if (!std::holds_alternative<double>(v)) return std::nullopt;
        double d = std::get<double>(v);
        if (d < 0.0) return std::nullopt;
        return static_cast<size_t>(d);
    }

    static signals::Value buffer_up_to(const signals::Value& current,
                                       const signals::Value& new_item,
                                       size_t max_n,
                                       bool /* cast_on_type_change */ = false) {
        signals::Value acc = append(current, new_item);
        if (max_n > 0 && std::holds_alternative<std::vector<double>>(acc)) {
            auto& v = std::get<std::vector<double>>(acc);
            if (v.size() > max_n)
                v.erase(v.begin(), v.begin() + static_cast<ptrdiff_t>(v.size() - max_n));
        }
        return acc;
    }

    static signals::Value add     (const signals::Value& a, const signals::Value& b) { return signals::add(a,b);      }
    static signals::Value subtract(const signals::Value& a, const signals::Value& b) { return signals::subtract(a,b); }
    static signals::Value multiply(const signals::Value& a, const signals::Value& b) { return signals::multiply(a,b); }
    static signals::Value rdivide (const signals::Value& a, const signals::Value& b) { return signals::rdivide(a,b);  }
    static signals::Value ldivide (const signals::Value& a, const signals::Value& b) { return signals::ldivide(a,b);  }
    static signals::Value gt(const signals::Value& a, const signals::Value& b) { return signals::gt(a,b); }
    static signals::Value ge(const signals::Value& a, const signals::Value& b) { return signals::ge(a,b); }
    static signals::Value lt(const signals::Value& a, const signals::Value& b) { return signals::lt(a,b); }
    static signals::Value le(const signals::Value& a, const signals::Value& b) { return signals::le(a,b); }
    static signals::Value eq(const signals::Value& a, const signals::Value& b) { return signals::eq(a,b); }
};

#endif // SIGNALS_VALUE_TRAITS_H
