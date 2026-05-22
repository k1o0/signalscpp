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
#include <sstream>
#include <string>
#include <vector>

template <>
struct ValueTraits<matlab::data::Array> {
    // Backing storage for appendValues on MATLAB struct arrays. Used by log()
    // so the committed history can grow geometrically while reads still see an
    // exact 1xN struct array.
    struct AppendStorage {
        bool active{ false };
        bool dirty{ false };
        size_t size{ 0 };
        size_t capacity{ 0 };
        std::vector<std::string> field_names;
        std::optional<matlab::data::Array> buffer;
    };

    // Backing storage for typed buffer_up_to nodes. `buffer` holds a fixed-size
    // ring, while `pending_*` captures the item/max_n used to build the current
    // transaction's preview value. apply() later commits that pending item.
    struct BufferStorage {
        bool active{ false };
        bool pending{ false };
        matlab::data::ArrayType type{ matlab::data::ArrayType::DOUBLE };
        size_t capacity{ 0 };
        size_t size{ 0 };
        size_t start{ 0 };
        std::optional<matlab::data::Array> buffer;
        std::optional<matlab::data::Array> pending_item;
        size_t pending_max_n{ 0 };
    };

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
        if (working.isEmpty()) return current;
        if (current.isEmpty()) return working;

        if (current.getType() == AT::STRUCT && working.getType() == AT::STRUCT)
            return append_struct(current, working, f);

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

    static bool append_storage_append(AppendStorage& storage,
                                      std::optional<matlab::data::Array>& current,
                                      const matlab::data::Array& working) {
        using AT = matlab::data::ArrayType;
        if (working.isEmpty() || working.getType() != AT::STRUCT)
            return false;

        matlab::data::ArrayFactory f;
        matlab::data::StructArray work = const_cast<matlab::data::Array&>(working);
        const auto work_field_names = collect_field_names(work);
        const size_t work_n = working.getNumberOfElements();

        if (!storage.active) {
            // First append: seed the backing store from any existing concrete
            // currentValue, then switch future growth to the overallocated store.
            size_t curr_n = 0;
            if (current && !current->isEmpty()) {
                if (current->getType() != AT::STRUCT)
                    return false;
                matlab::data::StructArray curr = const_cast<matlab::data::Array&>(*current);
                storage.field_names = collect_field_names(curr);
                if (storage.field_names != work_field_names)
                    throw signals::TypeError("append: struct field mismatch");
                curr_n = current->getNumberOfElements();
            } else {
                storage.field_names = work_field_names;
            }

            size_t needed = curr_n + work_n;
            size_t capacity = size_t(4);
            while (capacity < needed)
                capacity *= 2;

            storage.buffer = f.createStructArray({1, capacity}, storage.field_names);
            storage.active = true;
            storage.size = 0;
            storage.capacity = capacity;

            if (curr_n > 0) {
                matlab::data::StructArray curr = const_cast<matlab::data::Array&>(*current);
                matlab::data::StructArray buffer = as_struct(*storage.buffer);
                copy_struct_range(curr, curr_n, buffer, storage.field_names, 0);
                *storage.buffer = buffer;
                storage.size = curr_n;
            }
        } else if (storage.field_names != work_field_names) {
            throw signals::TypeError("append: struct field mismatch");
        }

        const size_t needed = storage.size + work_n;
        if (needed > storage.capacity) {
            // Grow geometrically so repeated log appends are amortized rather
            // than copying the whole history every post.
            size_t new_capacity = storage.capacity > 0 ? storage.capacity : size_t(4);
            while (new_capacity < needed)
                new_capacity *= 2;

            auto grown = f.createStructArray({1, new_capacity}, storage.field_names);
            matlab::data::StructArray buffer = as_struct(*storage.buffer);
            copy_struct_range(buffer, storage.size, grown, storage.field_names, 0);
            *storage.buffer = grown;
            storage.capacity = new_capacity;
        }

        matlab::data::StructArray buffer = as_struct(*storage.buffer);
        copy_struct_range(work, work_n, buffer, storage.field_names, storage.size);
        *storage.buffer = buffer;
        storage.size = needed;
        storage.dirty = true;
        current = std::nullopt;
        return true;
    }

    static bool append_storage_materialize(AppendStorage& storage,
                                           std::optional<matlab::data::Array>& current) {
        if (!storage.active)
            return false;
        if (!storage.dirty && current.has_value())
            return true;

        // Reads expose only the logical prefix [0, size), never the spare
        // capacity kept in the backing store.
        matlab::data::ArrayFactory f;
        auto out = f.createStructArray({1, storage.size}, storage.field_names);
        matlab::data::StructArray buffer = as_struct(*storage.buffer);
        copy_struct_range(buffer, storage.size, out, storage.field_names, 0);
        current = out;
        storage.dirty = false;
        return true;
    }

    static void append_storage_reset(AppendStorage& storage) {
        storage = AppendStorage{};
    }

    static bool buffer_storage_preview(BufferStorage& storage,
                                       const std::optional<matlab::data::Array>& current,
                                       std::optional<matlab::data::Array>& working,
                                       const matlab::data::Array& new_item,
                                       size_t max_n,
                                       bool cast_on_type_change) {
        // Only typed fixed-capacity buffers use the ring path. Mixed-type cell
        // mode and char buffering still fall back to the older materialized path.
        if (cast_on_type_change || max_n == 0 || !is_ring_buffer_type(new_item.getType()))
            return false;

        if (!ensure_ring_storage(storage, current, new_item.getType(), max_n))
            return false;

        if (storage.type != new_item.getType()) {
            const matlab::data::Array& curr =
                (current && !current->isEmpty()) ? *current : no_value();
            throw signals::TypeError(
                "bufferUpTo: value type changed from " + describe_array(curr) +
                " to " + describe_array(new_item) +
                "; use the 'cell' option to allow mixed types");
        }

        // Record the incoming item so apply() can commit exactly the previewed
        // transaction after downstream transfer logic has run.
        storage.pending = true;
        storage.pending_item = new_item;
        storage.pending_max_n = max_n;

        switch (storage.type) {
            case matlab::data::ArrayType::DOUBLE:
                working = preview_typed<double>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::SINGLE:
                working = preview_typed<float>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::INT8:
                working = preview_typed<int8_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::INT16:
                working = preview_typed<int16_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::INT32:
                working = preview_typed<int32_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::INT64:
                working = preview_typed<int64_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::UINT8:
                working = preview_typed<uint8_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::UINT16:
                working = preview_typed<uint16_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::UINT32:
                working = preview_typed<uint32_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::UINT64:
                working = preview_typed<uint64_t>(storage, new_item, max_n);
                return true;
            case matlab::data::ArrayType::LOGICAL:
                working = preview_typed<bool>(storage, new_item, max_n);
                return true;
            default:
                storage.pending = false;
                storage.pending_item = std::nullopt;
                return false;
        }
    }

    static bool buffer_storage_commit(BufferStorage& storage,
                                      const std::optional<matlab::data::Array>& /*working*/) {
        if (!storage.pending || !storage.pending_item)
            return false;

        // Commit mutates the fixed-capacity ring only after transfer() has
        // finished computing the visible preview value for this transaction.
        switch (storage.type) {
            case matlab::data::ArrayType::DOUBLE:
                commit_typed<double>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::SINGLE:
                commit_typed<float>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::INT8:
                commit_typed<int8_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::INT16:
                commit_typed<int16_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::INT32:
                commit_typed<int32_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::INT64:
                commit_typed<int64_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::UINT8:
                commit_typed<uint8_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::UINT16:
                commit_typed<uint16_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::UINT32:
                commit_typed<uint32_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::UINT64:
                commit_typed<uint64_t>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            case matlab::data::ArrayType::LOGICAL:
                commit_typed<bool>(storage, *storage.pending_item, storage.pending_max_n);
                break;
            default:
                return false;
        }

        storage.pending = false;
        storage.pending_item = std::nullopt;
        storage.pending_max_n = 0;
        return true;
    }

    static void buffer_storage_reset(BufferStorage& storage) {
        storage = BufferStorage{};
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

        const bool curr_empty = current.isEmpty();
        const bool curr_cell  = !curr_empty && current.getType() == AT::CELL;

        // ── Cell mode: current is already a cell array ───────────────────────
        if (curr_cell) {
            matlab::data::CellArray ca = const_cast<matlab::data::Array&>(current);
            std::vector<matlab::data::Array> cells;
            for (auto elem : ca) cells.push_back(elem);
            cells.push_back(new_item);
            if (max_n > 0 && cells.size() > max_n)
                cells.erase(cells.begin(),
                            cells.begin() + static_cast<ptrdiff_t>(cells.size() - max_n));
            auto out = f.createCellArray({1, cells.size()});
            for (size_t i = 0; i < cells.size(); ++i) out[0][i] = cells[i];
            return out;
        }

        // Empty buffers should adopt the type of their first value. Existing
        // typed buffers continue only when the incoming item has the same type.
        if (curr_empty || current.getType() == new_item.getType()) {
            switch (new_item.getType()) {
                case AT::DOUBLE:
                    return buffer_up_to_typed<double>(current, new_item, max_n);
                case AT::SINGLE:
                    return buffer_up_to_typed<float>(current, new_item, max_n);
                case AT::INT8:
                    return buffer_up_to_typed<int8_t>(current, new_item, max_n);
                case AT::INT16:
                    return buffer_up_to_typed<int16_t>(current, new_item, max_n);
                case AT::INT32:
                    return buffer_up_to_typed<int32_t>(current, new_item, max_n);
                case AT::INT64:
                    return buffer_up_to_typed<int64_t>(current, new_item, max_n);
                case AT::UINT8:
                    return buffer_up_to_typed<uint8_t>(current, new_item, max_n);
                case AT::UINT16:
                    return buffer_up_to_typed<uint16_t>(current, new_item, max_n);
                case AT::UINT32:
                    return buffer_up_to_typed<uint32_t>(current, new_item, max_n);
                case AT::UINT64:
                    return buffer_up_to_typed<uint64_t>(current, new_item, max_n);
                case AT::LOGICAL:
                    return buffer_up_to_typed<bool>(current, new_item, max_n);
                case AT::CHAR:
                    return buffer_up_to_char(current, new_item, max_n);
                default:
                    break;
            }
        }

        // ── Type mismatch ────────────────────────────────────────────────────
        if (!cast_on_type_change)
            throw signals::TypeError(
                "bufferUpTo: value type changed from " + describe_array(current) +
                " to " + describe_array(new_item) +
                "; use the 'cell' option to allow mixed types");

        // Promote existing typed buffer to a cell array, then append.
        std::vector<matlab::data::Array> cells;
        if (!curr_empty) {
            if (!append_cells_from_array(current, cells, f))
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

    // ── Arithmetic / comparison helpers ──────────────────────────────────────
    //
    // Both arguments must be DOUBLE arrays.  Otherwise: throw TypeError so the
    // network falls back to the @plus / @le / etc. callable (option ii).
    // Sizes must either match exactly or one side must be a scalar (broadcast).
    // Element-wise multiplication is used for `multiply` — matching MATLAB's
    // `.*` (and `*` for scalars).  Matrix multiplication (`*` on matrices) is
    // not natively supported; route those through map2/mapn with @mtimes.

private:
    static matlab::data::StructArray as_struct(matlab::data::Array& arr) {
        return arr;
    }

    static bool is_ring_buffer_type(matlab::data::ArrayType type) noexcept {
        using AT = matlab::data::ArrayType;
        switch (type) {
            case AT::DOUBLE:
            case AT::SINGLE:
            case AT::INT8:
            case AT::INT16:
            case AT::INT32:
            case AT::INT64:
            case AT::UINT8:
            case AT::UINT16:
            case AT::UINT32:
            case AT::UINT64:
            case AT::LOGICAL:
                return true;
            default:
                return false;
        }
    }

    static size_t ring_index(const BufferStorage& storage, size_t logical_index) {
        return (storage.start + logical_index) % storage.capacity;
    }

    static bool ensure_ring_storage(BufferStorage& storage,
                                    const std::optional<matlab::data::Array>& current,
                                    matlab::data::ArrayType item_type,
                                    size_t max_n) {
        if (storage.active) {
            if (storage.type != item_type)
                return true;
            if (storage.capacity != max_n)
                return resize_ring_storage(storage, max_n);
            return true;
        }

        storage.type = item_type;
        storage.capacity = max_n;
        storage.size = 0;
        storage.start = 0;
        if (!allocate_ring_buffer(storage))
            return false;
        storage.active = true;

        if (current && !current->isEmpty()) {
            // Rehydrate ring state from an existing concrete currentValue when a
            // buffer node first transitions onto the optimized storage path.
            if (!is_ring_buffer_type(current->getType()) || current->getType() != item_type)
                return false;
            append_current_into_storage(storage, *current);
        }
        return true;
    }

    static bool allocate_ring_buffer(BufferStorage& storage) {
        matlab::data::ArrayFactory f;
        switch (storage.type) {
            case matlab::data::ArrayType::DOUBLE:
                storage.buffer = f.createArray<double>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::SINGLE:
                storage.buffer = f.createArray<float>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::INT8:
                storage.buffer = f.createArray<int8_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::INT16:
                storage.buffer = f.createArray<int16_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::INT32:
                storage.buffer = f.createArray<int32_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::INT64:
                storage.buffer = f.createArray<int64_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::UINT8:
                storage.buffer = f.createArray<uint8_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::UINT16:
                storage.buffer = f.createArray<uint16_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::UINT32:
                storage.buffer = f.createArray<uint32_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::UINT64:
                storage.buffer = f.createArray<uint64_t>({1, storage.capacity}); return true;
            case matlab::data::ArrayType::LOGICAL:
                storage.buffer = f.createArray<bool>({1, storage.capacity}); return true;
            default:
                return false;
        }
    }

    static bool resize_ring_storage(BufferStorage& storage, size_t new_capacity) {
        if (storage.capacity == new_capacity)
            return true;

        BufferStorage resized;
        resized.active = true;
        resized.type = storage.type;
        resized.capacity = new_capacity;
        resized.size = 0;
        resized.start = 0;
        if (!allocate_ring_buffer(resized))
            return false;

        const size_t keep = std::min(storage.size, new_capacity);
        const size_t first_keep = storage.size > keep ? storage.size - keep : 0;

        switch (storage.type) {
            case matlab::data::ArrayType::DOUBLE:
                copy_ring_tail<double>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::SINGLE:
                copy_ring_tail<float>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::INT8:
                copy_ring_tail<int8_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::INT16:
                copy_ring_tail<int16_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::INT32:
                copy_ring_tail<int32_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::INT64:
                copy_ring_tail<int64_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::UINT8:
                copy_ring_tail<uint8_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::UINT16:
                copy_ring_tail<uint16_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::UINT32:
                copy_ring_tail<uint32_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::UINT64:
                copy_ring_tail<uint64_t>(storage, resized, first_keep, keep); break;
            case matlab::data::ArrayType::LOGICAL:
                copy_ring_tail<bool>(storage, resized, first_keep, keep); break;
            default:
                return false;
        }

        storage = std::move(resized);
        return true;
    }

    static void append_current_into_storage(BufferStorage& storage,
                                            const matlab::data::Array& current) {
        switch (storage.type) {
            case matlab::data::ArrayType::DOUBLE:
                append_array_into_storage<double>(storage, current); break;
            case matlab::data::ArrayType::SINGLE:
                append_array_into_storage<float>(storage, current); break;
            case matlab::data::ArrayType::INT8:
                append_array_into_storage<int8_t>(storage, current); break;
            case matlab::data::ArrayType::INT16:
                append_array_into_storage<int16_t>(storage, current); break;
            case matlab::data::ArrayType::INT32:
                append_array_into_storage<int32_t>(storage, current); break;
            case matlab::data::ArrayType::INT64:
                append_array_into_storage<int64_t>(storage, current); break;
            case matlab::data::ArrayType::UINT8:
                append_array_into_storage<uint8_t>(storage, current); break;
            case matlab::data::ArrayType::UINT16:
                append_array_into_storage<uint16_t>(storage, current); break;
            case matlab::data::ArrayType::UINT32:
                append_array_into_storage<uint32_t>(storage, current); break;
            case matlab::data::ArrayType::UINT64:
                append_array_into_storage<uint64_t>(storage, current); break;
            case matlab::data::ArrayType::LOGICAL:
                append_array_into_storage<bool>(storage, current); break;
            default:
                break;
        }
    }

    template <typename T>
    static void append_array_into_storage(BufferStorage& storage,
                                          const matlab::data::Array& arr) {
        matlab::data::TypedArray<T> src = const_cast<matlab::data::Array&>(arr);
        matlab::data::TypedArray<T> dst = const_cast<matlab::data::Array&>(*storage.buffer);
        for (const auto& value : src)
            ring_push(storage, dst, static_cast<T>(value));
        *storage.buffer = dst;
    }

    template <typename T>
    static void ring_push(BufferStorage& storage,
                          matlab::data::TypedArray<T>& dst,
                          T value) {
        if (storage.capacity == 0)
            return;
        if (storage.size < storage.capacity) {
            dst[ring_index(storage, storage.size)] = value;
            ++storage.size;
        } else {
            dst[storage.start] = value;
            storage.start = (storage.start + 1) % storage.capacity;
        }
    }

    template <typename T>
    static matlab::data::Array preview_typed(const BufferStorage& storage,
                                             const matlab::data::Array& new_item,
                                             size_t max_n) {
        matlab::data::TypedArray<T> src = const_cast<matlab::data::Array&>(new_item);
        const size_t new_count = new_item.getNumberOfElements();
        const size_t out_n = std::min(storage.size + new_count, max_n);

        matlab::data::ArrayFactory f;
        auto out = f.createArray<T>({1, out_n});

        if (new_count >= out_n) {
            // The new item alone overflows the window, so only its tail survives.
            const size_t skip = new_count - out_n;
            size_t out_idx = 0;
            size_t src_idx = 0;
            for (const auto& value : src) {
                if (src_idx++ < skip) continue;
                out[out_idx++] = static_cast<T>(value);
            }
            return out;
        }

        // Otherwise keep the newest logical prefix from the ring and append the
        // incoming item contiguously into the visible preview buffer.
        const size_t keep = out_n - new_count;
        matlab::data::TypedArray<T> buffer = const_cast<matlab::data::Array&>(*storage.buffer);
        const size_t first_keep = storage.size - keep;
        for (size_t i = 0; i < keep; ++i)
            out[i] = buffer[ring_index(storage, first_keep + i)];

        size_t out_idx = keep;
        for (const auto& value : src)
            out[out_idx++] = static_cast<T>(value);
        return out;
    }

    template <typename T>
    static void commit_typed(BufferStorage& storage,
                             const matlab::data::Array& new_item,
                             size_t max_n) {
        if (storage.capacity != max_n)
            resize_ring_storage(storage, max_n);

        // Commit writes the new item into the fixed-capacity ring in arrival
        // order, overwriting the oldest elements once the window is full.
        matlab::data::TypedArray<T> dst = const_cast<matlab::data::Array&>(*storage.buffer);
        matlab::data::TypedArray<T> src = const_cast<matlab::data::Array&>(new_item);
        for (const auto& value : src)
            ring_push(storage, dst, static_cast<T>(value));
        *storage.buffer = dst;
    }

    template <typename T>
    static void copy_ring_tail(const BufferStorage& from,
                               BufferStorage& to,
                               size_t first_keep,
                               size_t keep) {
        matlab::data::TypedArray<T> src = const_cast<matlab::data::Array&>(*from.buffer);
        matlab::data::TypedArray<T> dst = const_cast<matlab::data::Array&>(*to.buffer);
        for (size_t i = 0; i < keep; ++i)
            dst[i] = src[ring_index(from, first_keep + i)];
        to.size = keep;
        to.start = 0;
        *to.buffer = dst;
    }

    static const char* array_type_name(matlab::data::ArrayType type) noexcept {
        using AT = matlab::data::ArrayType;
        switch (type) {
            case AT::DOUBLE: return "double";
            case AT::SINGLE: return "single";
            case AT::LOGICAL: return "logical";
            case AT::CHAR: return "char";
            case AT::INT8: return "int8";
            case AT::INT16: return "int16";
            case AT::INT32: return "int32";
            case AT::INT64: return "int64";
            case AT::UINT8: return "uint8";
            case AT::UINT16: return "uint16";
            case AT::UINT32: return "uint32";
            case AT::UINT64: return "uint64";
            case AT::MATLAB_STRING: return "string";
            case AT::CELL: return "cell";
            case AT::STRUCT: return "struct";
            default: return "unknown";
        }
    }

    static std::string describe_array(const matlab::data::Array& arr) {
        std::ostringstream oss;
        if (arr.isEmpty() && arr.getType() == matlab::data::ArrayType::DOUBLE) {
            oss << "empty double sentinel";
        } else {
            oss << array_type_name(arr.getType());
        }
        oss << '[';
        const auto dims = arr.getDimensions();
        for (size_t i = 0; i < dims.size(); ++i) {
            if (i > 0) oss << 'x';
            oss << dims[i];
        }
        oss << ']';
        return oss.str();
    }

    template <typename T>
    static matlab::data::Array buffer_up_to_typed(const matlab::data::Array& current,
                                                  const matlab::data::Array& new_item,
                                                  size_t max_n) {
        matlab::data::ArrayFactory f;
        std::vector<T> acc;
        if (!current.isEmpty()) {
            matlab::data::TypedArray<T> ta = const_cast<matlab::data::Array&>(current);
            for (const auto& v : ta) acc.push_back(static_cast<T>(v));
        }
        {
            matlab::data::TypedArray<T> ta = const_cast<matlab::data::Array&>(new_item);
            for (const auto& v : ta) acc.push_back(static_cast<T>(v));
        }
        if (max_n > 0 && acc.size() > max_n)
            acc.erase(acc.begin(),
                      acc.begin() + static_cast<ptrdiff_t>(acc.size() - max_n));
        auto out = f.createArray<T>({1, acc.size()});
        for (size_t i = 0; i < acc.size(); ++i)
            out[i] = acc[i];
        return out;
    }

    static matlab::data::Array buffer_up_to_char(const matlab::data::Array& current,
                                                 const matlab::data::Array& new_item,
                                                 size_t max_n) {
        matlab::data::ArrayFactory f;
        std::string acc;
        if (!current.isEmpty()) {
            matlab::data::CharArray ca = const_cast<matlab::data::Array&>(current);
            acc = ca.toAscii();
        }
        {
            matlab::data::CharArray ca = const_cast<matlab::data::Array&>(new_item);
            acc += ca.toAscii();
        }
        if (max_n > 0 && acc.size() > max_n)
            acc.erase(0, acc.size() - max_n);
        return f.createCharArray(acc);
    }

    static matlab::data::Array append_struct(const matlab::data::Array& current,
                                             const matlab::data::Array& working,
                                             matlab::data::ArrayFactory& f) {
        matlab::data::StructArray curr = const_cast<matlab::data::Array&>(current);
        matlab::data::StructArray work = const_cast<matlab::data::Array&>(working);

        std::vector<std::string> field_names = collect_field_names(curr);
        std::vector<std::string> work_field_names = collect_field_names(work);

        if (field_names != work_field_names)
            throw signals::TypeError("append: struct field mismatch");

        const size_t curr_n = current.getNumberOfElements();
        const size_t work_n = working.getNumberOfElements();
        auto out = f.createStructArray({1, curr_n + work_n}, field_names);

        copy_struct_range(curr, curr_n, out, field_names, 0);
        copy_struct_range(work, work_n, out, field_names, curr_n);
        return out;
    }

    static std::vector<std::string> collect_field_names(const matlab::data::StructArray& arr) {
        std::vector<std::string> field_names;
        for (const auto& field_id : arr.getFieldNames())
            field_names.push_back(static_cast<std::string>(field_id));
        return field_names;
    }

    static void copy_struct_range(const matlab::data::StructArray& src,
                                  size_t count,
                                  matlab::data::StructArray& dst,
                                  const std::vector<std::string>& field_names,
                                  size_t dst_offset) {
        for (size_t i = 0; i < count; ++i) {
            for (const auto& field_name : field_names)
                dst[dst_offset + i][field_name] = src[i][field_name];
        }
    }

    template <typename T>
    static void append_cells_from_typed(const matlab::data::Array& current,
                                        std::vector<matlab::data::Array>& cells,
                                        matlab::data::ArrayFactory& f) {
        matlab::data::TypedArray<T> ta = const_cast<matlab::data::Array&>(current);
        for (const auto& v : ta)
            cells.push_back(f.createScalar<T>(static_cast<T>(v)));
    }

    static bool append_cells_from_array(const matlab::data::Array& current,
                                        std::vector<matlab::data::Array>& cells,
                                        matlab::data::ArrayFactory& f) {
        using AT = matlab::data::ArrayType;
        switch (current.getType()) {
            case AT::DOUBLE: append_cells_from_typed<double>(current, cells, f); return true;
            case AT::SINGLE: append_cells_from_typed<float>(current, cells, f); return true;
            case AT::LOGICAL: append_cells_from_typed<bool>(current, cells, f); return true;
            case AT::INT8: append_cells_from_typed<int8_t>(current, cells, f); return true;
            case AT::INT16: append_cells_from_typed<int16_t>(current, cells, f); return true;
            case AT::INT32: append_cells_from_typed<int32_t>(current, cells, f); return true;
            case AT::INT64: append_cells_from_typed<int64_t>(current, cells, f); return true;
            case AT::UINT8: append_cells_from_typed<uint8_t>(current, cells, f); return true;
            case AT::UINT16: append_cells_from_typed<uint16_t>(current, cells, f); return true;
            case AT::UINT32: append_cells_from_typed<uint32_t>(current, cells, f); return true;
            case AT::UINT64: append_cells_from_typed<uint64_t>(current, cells, f); return true;
            case AT::CHAR: {
                matlab::data::CharArray ca = const_cast<matlab::data::Array&>(current);
                std::string chars = ca.toAscii();
                for (char ch : chars)
                    cells.push_back(f.createCharArray(std::string(1, ch)));
                return true;
            }
            default:
                return false;
        }
    }

    template <typename Out, typename Op>
    static matlab::data::Array binop_double(
        const matlab::data::Array& a,
        const matlab::data::Array& b,
        Op op,
        const char* what)
    {
        using AT = matlab::data::ArrayType;
        if (a.getType() != AT::DOUBLE || b.getType() != AT::DOUBLE)
            throw signals::TypeError(std::string(what) + ": non-double inputs");

        matlab::data::TypedArray<double> ta = const_cast<matlab::data::Array&>(a);
        matlab::data::TypedArray<double> tb = const_cast<matlab::data::Array&>(b);
        const size_t na = a.getNumberOfElements();
        const size_t nb = b.getNumberOfElements();

        matlab::data::ArrayFactory f;
        if (na == 1 && nb == 1) {
            return f.createScalar<Out>(static_cast<Out>(op(double(ta[0]), double(tb[0]))));
        }
        if (na == 1) {
            const double av = double(ta[0]);
            auto out = f.createArray<Out>(b.getDimensions());
            for (size_t i = 0; i < nb; ++i)
                out[i] = static_cast<Out>(op(av, double(tb[i])));
            return out;
        }
        if (nb == 1) {
            const double bv = double(tb[0]);
            auto out = f.createArray<Out>(a.getDimensions());
            for (size_t i = 0; i < na; ++i)
                out[i] = static_cast<Out>(op(double(ta[i]), bv));
            return out;
        }
        if (a.getDimensions() != b.getDimensions())
            throw signals::TypeError(std::string(what) + ": shape mismatch");
        auto out = f.createArray<Out>(a.getDimensions());
        for (size_t i = 0; i < na; ++i)
            out[i] = static_cast<Out>(op(double(ta[i]), double(tb[i])));
        return out;
    }

public:
    static matlab::data::Array add(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<double>(a, b, [](double x, double y) { return x + y; }, "add");
    }
    static matlab::data::Array subtract(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<double>(a, b, [](double x, double y) { return x - y; }, "subtract");
    }
    static matlab::data::Array multiply(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<double>(a, b, [](double x, double y) { return x * y; }, "multiply");
    }
    static matlab::data::Array rdivide(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<double>(a, b, [](double x, double y) { return x / y; }, "rdivide");
    }
    static matlab::data::Array ldivide(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<double>(a, b, [](double x, double y) { return y / x; }, "ldivide");
    }
    static matlab::data::Array gt(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<bool>(a, b, [](double x, double y) { return x > y; }, "gt");
    }
    static matlab::data::Array ge(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<bool>(a, b, [](double x, double y) { return x >= y; }, "ge");
    }
    static matlab::data::Array lt(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<bool>(a, b, [](double x, double y) { return x < y; }, "lt");
    }
    static matlab::data::Array le(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<bool>(a, b, [](double x, double y) { return x <= y; }, "le");
    }
    static matlab::data::Array eq(const matlab::data::Array& a, const matlab::data::Array& b) {
        return binop_double<bool>(a, b, [](double x, double y) { return x == y; }, "eq");
    }
};
