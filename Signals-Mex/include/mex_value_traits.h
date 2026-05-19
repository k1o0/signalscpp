#pragma once
// mex_value_traits.h — ValueTraits<matlab::data::Array> specialisation.
//
// Include this file in translation units that instantiate NetworkT<matlab::data::Array>
// (i.e. mex_network.cpp) and in mx_ops.cpp where it is needed for has_value checks.

#include "value_traits.h"       // primary ValueTraits<V> template
#include "value.h"              // signals::TypeError
#include "MatlabDataArray.hpp"

#include <cstddef>
#include <optional>
#include <vector>

template <>
struct ValueTraits<matlab::data::Array> {

    // ── Existence / truthiness ───────────────────────────────────────────────

    static bool has_value(const matlab::data::Array& v) noexcept {
        return !v.isEmpty();
    }

    static bool is_truthy(const matlab::data::Array& v) noexcept {
        if (v.isEmpty()) return false;
        using AT = matlab::data::ArrayType;
        try {
            switch (v.getType()) {
                case AT::LOGICAL: {
                    matlab::data::TypedArray<bool> ta =
                        const_cast<matlab::data::Array&>(v);
                    return bool(ta[0]);
                }
                case AT::DOUBLE: {
                    matlab::data::TypedArray<double> ta =
                        const_cast<matlab::data::Array&>(v);
                    return double(ta[0]) != 0.0;
                }
                default:
                    return true;  // non-empty, non-numeric → truthy
            }
        } catch (...) { return false; }
    }

    // Fast C++ equality for numeric arrays.  Throws signals::TypeError for any
    // other type so that transfer() can fall back to a MATLAB isequal() call —
    // mirroring the legacy mexnet pattern of fast-scalar-C-path + transferInMATLAB
    // fallback for non-scalar/non-double inputs.
    static bool values_equal(const matlab::data::Array& a,
                             const matlab::data::Array& b) {
        using AT = matlab::data::ArrayType;
        if (a.getType() != b.getType()) return false;
        if (a.getNumberOfElements() != b.getNumberOfElements()) return false;
        if (a.getType() == AT::DOUBLE) {
            try {
                matlab::data::TypedArray<double> ta =
                    const_cast<matlab::data::Array&>(a);
                matlab::data::TypedArray<double> tb =
                    const_cast<matlab::data::Array&>(b);
                for (size_t i = 0; i < a.getNumberOfElements(); ++i)
                    if (double(ta[i]) != double(tb[i])) return false;
                return true;
            } catch (...) { return false; }
        }
        // Non-double: can't determine equality in C++ — caller should use isequal().
        throw signals::TypeError("values_equal: type requires MATLAB isequal() fallback");
    }

    // ── Sentinel ─────────────────────────────────────────────────────────────

    // Returns an empty (0×0) double array — the "no value" sentinel.
    // Created fresh each call; only used at MEX boundary, not in the hot path.
    static matlab::data::Array no_value() {
        matlab::data::ArrayFactory f;
        return f.createArray<double>({0, 0});
    }

    // ── Scalar constructors ──────────────────────────────────────────────────

    static matlab::data::Array from_bool(bool b) {
        matlab::data::ArrayFactory f;
        return f.createScalar<bool>(b);
    }

    static matlab::data::Array from_double(double d) {
        matlab::data::ArrayFactory f;
        return f.createScalar<double>(d);
    }

    // ── numel ────────────────────────────────────────────────────────────────

    static double numel(const matlab::data::Array& v) noexcept {
        return static_cast<double>(v.getNumberOfElements());
    }

    // ── append (buffer / bufferUpTo) ─────────────────────────────────────────

    // Concatenate working onto current as a flat 1×N double row vector.
    // Non-double types are silently ignored (same behaviour as signals::Value append).
    static matlab::data::Array append(const matlab::data::Array& current,
                                      const matlab::data::Array& working) {
        matlab::data::ArrayFactory f;
        using AT = matlab::data::ArrayType;
        std::vector<double> acc;
        auto push = [&acc](const matlab::data::Array& arr) {
            if (arr.getType() == AT::DOUBLE && !arr.isEmpty()) {
                matlab::data::TypedArray<double> ta =
                    const_cast<matlab::data::Array&>(arr);
                for (double d : ta) acc.push_back(d);
            }
        };
        push(current);
        push(working);
        if (acc.empty()) return f.createArray<double>({1, 0});
        auto out = f.createArray<double>({1, acc.size()});
        std::copy(acc.begin(), acc.end(), out.begin());
        return out;
    }

    // ── to_index (select_from) ───────────────────────────────────────────────

    static std::optional<size_t> to_index(const matlab::data::Array& v) {
        using AT = matlab::data::ArrayType;
        if (v.getType() != AT::DOUBLE || v.getNumberOfElements() != 1)
            return std::nullopt;
        try {
            matlab::data::TypedArray<double> ta =
                const_cast<matlab::data::Array&>(v);
            double d = double(ta[0]);
            if (d < 0.0) return std::nullopt;
            return static_cast<size_t>(d);
        } catch (...) { return std::nullopt; }
    }

    // ── buffer_up_to ─────────────────────────────────────────────────────────
    // Default (strict, cast_on_type_change=false):
    //   Items must be double scalars/vectors; buffer is a 1×N double row vector.
    //   Raises signals::TypeError on type change (matching legacy behaviour).
    //
    // Cast mode (cast_on_type_change=true):
    //   Items of any type are accepted.  On a type change the existing typed
    //   buffer is promoted to a cell array (each scalar element becomes its own
    //   cell) and accumulation continues in cell mode.
    //
    // Mode is selected by the caller (network_impl.h) via the callable-presence
    // convention: callable set → cast mode; no callable → strict mode.
    static matlab::data::Array buffer_up_to(const matlab::data::Array& current,
                                            const matlab::data::Array& new_item,
                                            size_t max_n,
                                            bool cast_on_type_change = false) {
        matlab::data::ArrayFactory f;
        using AT = matlab::data::ArrayType;

        const bool curr_empty  = current.isEmpty();
        const bool curr_double = !curr_empty && current.getType() == AT::DOUBLE;
        const bool curr_cell   = !curr_empty && current.getType() == AT::CELL;
        const bool item_double = new_item.getType() == AT::DOUBLE;

        // ── Cell mode: current is already a cell array ───────────────────────
        if (curr_cell) {
            matlab::data::CellArray ca = const_cast<matlab::data::Array&>(current);
            std::vector<matlab::data::Array> cells;
            for (auto& elem : ca) cells.push_back(elem);
            cells.push_back(new_item);
            if (max_n > 0 && cells.size() > max_n)
                cells.erase(cells.begin(),
                            cells.begin() + static_cast<ptrdiff_t>(cells.size() - max_n));
            auto out = f.createCellArray({1, cells.size()});
            for (size_t i = 0; i < cells.size(); ++i) out[0][i] = cells[i];
            return out;
        }

        // ── Typed double path: current empty or double, new item is double ───
        if ((curr_empty || curr_double) && item_double) {
            std::vector<double> acc;
            if (curr_double) {
                matlab::data::TypedArray<double> ta =
                    const_cast<matlab::data::Array&>(current);
                for (double d : ta) acc.push_back(d);
            }
            {
                matlab::data::TypedArray<double> ta =
                    const_cast<matlab::data::Array&>(new_item);
                for (double d : ta) acc.push_back(d);
            }
            if (max_n > 0 && acc.size() > max_n)
                acc.erase(acc.begin(),
                          acc.begin() + static_cast<ptrdiff_t>(acc.size() - max_n));
            auto out = f.createArray<double>({1, acc.size()});
            std::copy(acc.begin(), acc.end(), out.begin());
            return out;
        }

        // ── Type mismatch ────────────────────────────────────────────────────
        if (!cast_on_type_change)
            throw signals::TypeError(
                "bufferUpTo: value type changed; use the 'cell' option to allow mixed types");

        // Promote existing typed (double) buffer to a cell array, then append.
        std::vector<matlab::data::Array> cells;
        if (curr_double) {
            matlab::data::TypedArray<double> ta =
                const_cast<matlab::data::Array&>(current);
            for (double d : ta) cells.push_back(f.createScalar<double>(d));
        } else if (!curr_empty) {
            cells.push_back(current);
        }
        cells.push_back(new_item);
        if (max_n > 0 && cells.size() > max_n)
            cells.erase(cells.begin(),
                        cells.begin() + static_cast<ptrdiff_t>(cells.size() - max_n));
        auto out = f.createCellArray({1, cells.size()});
        for (size_t i = 0; i < cells.size(); ++i) out[0][i] = cells[i];
        return out;
    }

    // ── Arithmetic — throw TypeError; MEX routes arithmetic via mapn_op/@plus ─

    static matlab::data::Array add(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("add not implemented for matlab::data::Array"); }
    static matlab::data::Array subtract(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("subtract not implemented for matlab::data::Array"); }
    static matlab::data::Array multiply(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("multiply not implemented for matlab::data::Array"); }
    static matlab::data::Array rdivide(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("rdivide not implemented for matlab::data::Array"); }
    static matlab::data::Array ldivide(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("ldivide not implemented for matlab::data::Array"); }
    static matlab::data::Array gt(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("gt not implemented for matlab::data::Array"); }
    static matlab::data::Array ge(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("ge not implemented for matlab::data::Array"); }
    static matlab::data::Array lt(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("lt not implemented for matlab::data::Array"); }
    static matlab::data::Array le(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("le not implemented for matlab::data::Array"); }
    static matlab::data::Array eq(const matlab::data::Array&, const matlab::data::Array&)
        { throw signals::TypeError("eq not implemented for matlab::data::Array"); }
};
