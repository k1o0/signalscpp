cmake_minimum_required(VERSION 3.21)
project(CppSignals VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(SIGNALSCPP_BUILD_MEX "Build MATLAB MEX bindings via libmexclass" OFF)

# ---------------------------------------------------------------------------
# Signals core static library
# ---------------------------------------------------------------------------
add_library(signals_core STATIC
    Signals/network.cpp
    Signals/value.cpp
)
target_include_directories(signals_core PUBLIC Signals)
target_compile_features(signals_core PUBLIC cxx_std_17)
# When building as a static library, strip dllexport/dllimport decorations.
target_compile_definitions(signals_core
    PRIVATE SIGNALS_EXPORTS       # marks symbols as dllexport in the .lib itself (ignored at link)
    PUBLIC  SIGNALS_STATIC_LIB    # consumers see SIGNALS_API as empty
)

# ---------------------------------------------------------------------------
# MEX bindings (optional)
# ---------------------------------------------------------------------------
if(SIGNALSCPP_BUILD_MEX)

    # Require MATLAB
    set(Matlab_ROOT_DIR "C:/Program Files/MATLAB/R2025a" CACHE PATH "MATLAB installation root")
    find_package(Matlab REQUIRED COMPONENTS MX_LIBRARY MEX_LIBRARY ENGINE_LIBRARY DATAARRAY_LIBRARY)

    # libmexclass — already cloned as a submodule at extern/libmexclass
    set(LIBMEXCLASS_SOURCE_DIR "${CMAKE_SOURCE_DIR}/extern/libmexclass/libmexclass/cpp")
    add_subdirectory(${LIBMEXCLASS_SOURCE_DIR} "${CMAKE_BINARY_DIR}/libmexclass")

    # Proxy sources
    set(MEX_DIR "${CMAKE_SOURCE_DIR}/Signals/mex")
    set(PROXY_SOURCES
        "${MEX_DIR}/proxy/CustomProxyFactory.cpp"
        "${MEX_DIR}/proxy/NetworkProxy.cpp"
    )

    libmexclass_client_add_proxy_library(
        NAME signalsproxy
        SOURCES ${PROXY_SOURCES}
        INCLUDE_DIRS "${MEX_DIR}/proxy" "${MEX_DIR}/include" "${CMAKE_SOURCE_DIR}/Signals"
        LINK_LIBRARIES signals_core
    )
    target_compile_features(signalsproxy PRIVATE cxx_std_17)

    # MEX gateway
    libmexclass_client_add_mex_gateway(
        NAME gateway
        CLIENT_PROXY_LIBRARY_NAME signalsproxy
        SOURCES "${MEX_DIR}/mex/gateway.cpp"
    )

    # Install gateway + proxy lib + libmexclass shared lib into the MATLAB package tree
    libmexclass_client_install(
        CLIENT_PROXY_LIBRARY_NAME signalsproxy
        CLIENT_MEX_GATEWAY_NAME gateway
        DESTINATION "Signals/mex/matlab"
    )

endif()
