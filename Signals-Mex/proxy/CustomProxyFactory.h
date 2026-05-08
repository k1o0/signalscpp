#pragma once

#include "libmexclass/proxy/Factory.h"

namespace sq::proxy {

class CustomProxyFactory : public libmexclass::proxy::Factory {
  public:
    libmexclass::proxy::MakeResult make_proxy(
        const libmexclass::proxy::ClassName& class_name,
        const libmexclass::proxy::FunctionArguments& constructor_arguments) override;
};

} // namespace sq::proxy
