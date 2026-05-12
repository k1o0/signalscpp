#pragma once
// python_value_traits.h — ValueTraits<pybind11::object> stub.
//
// STUB: implementations are placeholders.  Wire up properly once the
// pybind11 dependency and Python extension module are added to the build.
//
// To instantiate the Python binding:
//   #include "python_value_traits.h"
//   #include "network_impl.h"
//   template class NetworkT<pybind11::object>;

#include "value_traits.h"   // primary ValueTraits<V> template
#include "value.h"          // signals::TypeError

// Forward-declare so this header does not require pybind11 to be on the
// include path unless the user actually uses it.
namespace pybind11 { class object; }

template <>
struct ValueTraits<pybind11::object> {

    static bool has_value(const pybind11::object& v) noexcept;
    static bool is_truthy(const pybind11::object& v) noexcept;
    static bool values_equal(const pybind11::object& a,
                             const pybind11::object& b) noexcept;
    static pybind11::object no_value();
    static pybind11::object from_bool(bool b);
    static pybind11::object from_double(double d);
    static double numel(const pybind11::object& v) noexcept;
    static pybind11::object append(const pybind11::object& current,
                                   const pybind11::object& working);
    static std::optional<size_t> to_index(const pybind11::object& v);

    // Arithmetic — throw TypeError until native implementations are added.
    static pybind11::object add(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("add not implemented for pybind11::object"); }
    static pybind11::object subtract(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("subtract not implemented for pybind11::object"); }
    static pybind11::object multiply(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("multiply not implemented for pybind11::object"); }
    static pybind11::object rdivide(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("rdivide not implemented for pybind11::object"); }
    static pybind11::object ldivide(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("ldivide not implemented for pybind11::object"); }
    static pybind11::object gt(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("gt not implemented for pybind11::object"); }
    static pybind11::object ge(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("ge not implemented for pybind11::object"); }
    static pybind11::object lt(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("lt not implemented for pybind11::object"); }
    static pybind11::object le(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("le not implemented for pybind11::object"); }
    static pybind11::object eq(const pybind11::object&, const pybind11::object&)
        { throw signals::TypeError("eq not implemented for pybind11::object"); }
};
