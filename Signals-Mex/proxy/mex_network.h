#pragma once
// mex_network.h — convenience header for the MEX proxy layer.
//
// Defines MexNetwork = NetworkT<matlab::data::Array> and suppresses implicit
// instantiation so that only mex_network.cpp pays the compile cost.

#include "mex_value_traits.h"   // ValueTraits<matlab::data::Array>
#include "network.h"            // NetworkT<V> template declaration

// Type alias used throughout the MEX proxy layer.
using MexNetwork = NetworkT<matlab::data::Array>;

// Prevent re-instantiation in every TU that includes this header.
extern template class NetworkT<matlab::data::Array>;
