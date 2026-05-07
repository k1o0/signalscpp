// gateway.cpp — single MEX entry point for all Signals proxy operations.
// Follows the libmexclass pattern exactly: the MexFunction forwards every
// call to libmexclass::mex::gateway<> which handles Create / Destroy /
// MethodCall dispatch using our CustomProxyFactory.

#include "mex.hpp"
#include "mexAdapter.hpp"

#include "libmexclass/mex/gateway.h"

#include "CustomProxyFactory.h"

class MexFunction : public matlab::mex::Function {
  public:
    void operator()(matlab::mex::ArgumentList outputs,
                    matlab::mex::ArgumentList inputs)
    {
        libmexclass::mex::gateway<sq::proxy::CustomProxyFactory>(
            inputs, outputs, getEngine());
    }
};
