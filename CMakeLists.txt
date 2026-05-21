cmake_minimum_required(VERSION 3.21)
project(CppSignals VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default install prefix: project-root/matlab so `cmake --install` drops
# gateway.mexw64 and +libmexclass/ directly into the MATLAB source tree.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${CMAKE_SOURCE_DIR}/matlab"
        CACHE PATH "Install prefix (MATLAB package root)" FORCE)
endif()

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

    # Require MATLAB. Keep a Windows-friendly default, but avoid hard-coding
    # a platform-incompatible path on macOS/Linux.
    if(WIN32 AND NOT DEFINED Matlab_ROOT_DIR)
        set(Matlab_ROOT_DIR "C:/Program Files/MATLAB/R2025a" CACHE PATH "MATLAB installation root")
    endif()
    find_package(Matlab REQUIRED COMPONENTS MX_LIBRARY MEX_LIBRARY ENGINE_LIBRARY DATAARRAY_LIBRARY)

    # libmexclass — already cloned as a submodule at extern/libmexclass
    set(LIBMEXCLASS_SOURCE_DIR "${CMAKE_SOURCE_DIR}/extern/libmexclass/libmexclass/cpp")
    add_subdirectory(${LIBMEXCLASS_SOURCE_DIR} "${CMAKE_BINARY_DIR}/libmexclass")

    # Proxy sources — live in Signals-Mex/
    set(MEX_DIR "${CMAKE_SOURCE_DIR}/Signals-Mex")
    set(PROXY_SOURCES
        "${MEX_DIR}/proxy/CustomProxyFactory.cpp"
        "${MEX_DIR}/proxy/mex_network.cpp"
        "${MEX_DIR}/proxy/NetworkProxy.cpp"
        "${MEX_DIR}/proxy/NodeProxy.cpp"
        "${MEX_DIR}/plugins/mx_ops.cpp"
    )

    libmexclass_client_add_proxy_library(
        NAME signalsproxy
        SOURCES ${PROXY_SOURCES}
        INCLUDE_DIRS
            "${MEX_DIR}/proxy"
            "${MEX_DIR}/include"
            "${MEX_DIR}/plugins"
            "${CMAKE_SOURCE_DIR}/Signals"
        LINK_LIBRARIES signals_core
    )
    target_compile_features(signalsproxy PRIVATE cxx_std_17)

    # Regenerate matlab/+sig/OpCode.m from Signals/transferer.h.
    # Use a CMake script so generation is platform-independent.
    set(OPCODE_HEADER "${CMAKE_SOURCE_DIR}/Signals/transferer.h")
    set(OPCODE_MATLAB "${CMAKE_SOURCE_DIR}/matlab/+sig/OpCode.m")
    set(OPCODE_GENERATOR "${CMAKE_SOURCE_DIR}/scripts/gen_opcodes.cmake")

    add_custom_command(
        OUTPUT "${OPCODE_MATLAB}"
        COMMAND ${CMAKE_COMMAND}
                "-DHEADER_FILE=${OPCODE_HEADER}"
                "-DOUTPUT_FILE=${OPCODE_MATLAB}"
                -P "${OPCODE_GENERATOR}"
        DEPENDS
            "${OPCODE_HEADER}"
            "${OPCODE_GENERATOR}"
        VERBATIM
        COMMENT "Generating matlab/+sig/OpCode.m from Signals/transferer.h"
    )
    add_custom_target(generate_opcodes DEPENDS "${OPCODE_MATLAB}")
    add_dependencies(signalsproxy generate_opcodes)

    # MEX gateway
    libmexclass_client_add_mex_gateway(
        NAME gateway
        CLIENT_PROXY_LIBRARY_NAME signalsproxy
        SOURCES "${MEX_DIR}/gateway/gateway.cpp"
    )

    # Install gateway + proxy lib + libmexclass shared lib directly into
    # matlab/ (the CMAKE_INSTALL_PREFIX set above).
    libmexclass_client_install(
        CLIENT_PROXY_LIBRARY_NAME signalsproxy
        CLIENT_MEX_GATEWAY_NAME gateway
        DESTINATION "."
    )

endif()
