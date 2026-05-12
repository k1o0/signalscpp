// network.cpp — explicit instantiation of NetworkT<signals::Value>.
// Template method bodies live in network_impl.h.

#include "network_impl.h"

// Force all NetworkT<signals::Value> methods to be compiled into signals_core.
template class NetworkT<signals::Value>;
