#include "CustomProxyFactory.h"
#include "NetworkProxy.h"
#include "NodeProxy.h"

namespace sq::proxy {

libmexclass::proxy::MakeResult CustomProxyFactory::make_proxy(
    const libmexclass::proxy::ClassName& class_name,
    const libmexclass::proxy::FunctionArguments& constructor_arguments)
{
    REGISTER_PROXY(sig.NetworkProxy, sq::proxy::NetworkProxy);
    REGISTER_PROXY(sig.NodeProxy,    sq::proxy::NodeProxy);

    return libmexclass::error::Error{
        "sq:signals:unknownProxy",
        std::string("Unknown proxy class: ") + class_name};
}

} // namespace sq::proxy
