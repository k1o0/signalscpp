// mex_network.cpp — explicit instantiation of NetworkT<matlab::data::Array>.
// Template method bodies come from network_impl.h; value traits from mex_value_traits.h.

#include "mex_value_traits.h"
#include "network_impl.h"

// Force all NetworkT<matlab::data::Array> methods to be compiled into signalsproxy.
template class NetworkT<matlab::data::Array>;
