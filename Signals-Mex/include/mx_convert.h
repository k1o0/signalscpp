#pragma once
// mx_convert.h — header-only bidirectional conversion between signals::Value
// and matlab::data::Array.  Include after MatlabDataArray.hpp.

#include "value.h"
#include "MatlabDataArray.hpp"

#include <string>
#include <vector>

namespace sq::mex {

/// signals::Value  →  matlab::data::Array
///   monostate         []  (0×0 double)
///   double            scalar double
///   bool              scalar logical
///   std::string       scalar string
///   vector<double>    1×N double row vector
inline matlab::data::Array toMda(const signals::Value& v,
                                  matlab::data::ArrayFactory& f)
{
    struct Visitor {
        matlab::data::ArrayFactory& f;
        matlab::data::Array operator()(std::monostate)        const { return f.createArray<double>({0,0}); }
        matlab::data::Array operator()(double d)              const { return f.createScalar<double>(d); }
        matlab::data::Array operator()(bool b)                const { return f.createScalar<bool>(b); }
        matlab::data::Array operator()(const std::string& s)  const { return f.createCharArray(s); }
        matlab::data::Array operator()(const std::vector<double>& vec) const {
            auto arr = f.createArray<double>({1, vec.size()});
            std::copy(vec.begin(), vec.end(), arr.begin());
            return arr;
        }
    };
    return std::visit(Visitor{f}, v);
}

/// matlab::data::Array  →  signals::Value
///   empty              monostate
///   logical scalar     bool
///   double scalar      double
///   double array       vector<double>
///   string/char        std::string
///
/// Throws std::invalid_argument for unsupported types.
inline signals::Value fromMda(const matlab::data::Array& arr)
{
    using AT = matlab::data::ArrayType;
    if (arr.isEmpty()) return {};

    switch (arr.getType()) {
        case AT::LOGICAL: {
            matlab::data::TypedArray<bool> ta = arr;
            return bool(ta[0]);
        }
        case AT::DOUBLE: {
            matlab::data::TypedArray<double> ta = arr;
            if (arr.getNumberOfElements() == 1)
                return double(ta[0]);
            std::vector<double> v(arr.getNumberOfElements());
            std::copy(ta.begin(), ta.end(), v.begin());
            return v;
        }
        case AT::SINGLE: {
            matlab::data::TypedArray<float> ta = arr;
            return double(float(ta[0]));
        }
        case AT::INT8:   { matlab::data::TypedArray<int8_t>   ta=arr; return double(int8_t(ta[0])); }
        case AT::INT16:  { matlab::data::TypedArray<int16_t>  ta=arr; return double(int16_t(ta[0])); }
        case AT::INT32:  { matlab::data::TypedArray<int32_t>  ta=arr; return double(int32_t(ta[0])); }
        case AT::INT64:  { matlab::data::TypedArray<int64_t>  ta=arr; return double(int64_t(ta[0])); }
        case AT::UINT8:  { matlab::data::TypedArray<uint8_t>  ta=arr; return double(uint8_t(ta[0])); }
        case AT::UINT16: { matlab::data::TypedArray<uint16_t> ta=arr; return double(uint16_t(ta[0])); }
        case AT::UINT32: { matlab::data::TypedArray<uint32_t> ta=arr; return double(uint32_t(ta[0])); }
        case AT::UINT64: { matlab::data::TypedArray<uint64_t> ta=arr; return double(uint64_t(ta[0])); }
        case AT::MATLAB_STRING: {
            matlab::data::StringArray sa = arr;
            return std::string(sa[0]);
        }
        case AT::CHAR: {
            matlab::data::CharArray ca = arr;
            return ca.toAscii();
        }
        default:
            throw std::invalid_argument("sq:unsupportedType: unsupported MATLAB array type for signals::Value conversion");
    }
}

} // namespace sq::mex
