cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED HEADER_FILE)
    message(FATAL_ERROR "HEADER_FILE was not provided")
endif()
if(NOT DEFINED OUTPUT_FILE)
    message(FATAL_ERROR "OUTPUT_FILE was not provided")
endif()

file(READ "${HEADER_FILE}" HEADER_TEXT)
string(REPLACE "\r\n" "\n" HEADER_TEXT "${HEADER_TEXT}")
string(REPLACE "\r" "\n" HEADER_TEXT "${HEADER_TEXT}")
string(REPLACE "\n" ";" HEADER_LINES "${HEADER_TEXT}")

set(MATLAB_RESERVED_WORDS
    break case catch classdef continue else elseif end for function global if
    otherwise parfor persistent return spmd switch try while
)
set(MATLAB_METHOD_NAMES
    plus minus times mtimes rdivide ldivide mrdivide mldivide power mpower uminus uplus
    eq ne lt le gt ge and or not ctranspose transpose colon horzcat vertcat
    subsref subsasgn subsindex abs sign floor ceil round mod rem sum prod cumsum cumprod
    max min sort any all numel size length ndims isempty isnumeric islogical
    display disp char string double single logical
    int8 int16 int32 int64 uint8 uint16 uint32 uint64
)

set(IN_ENUM FALSE)
set(ENTRIES)
foreach(LINE IN LISTS HEADER_LINES)
    string(REGEX REPLACE "//.*$" "" STRIPPED "${LINE}")
    string(STRIP "${STRIPPED}" STRIPPED)

    if(NOT IN_ENUM)
        if(STRIPPED MATCHES "^enum[ \\t]+class[ \\t]+.*Operation[ \\t]*\\{")
            set(IN_ENUM TRUE)
        endif()
        continue()
    endif()

    if(STRIPPED MATCHES "^\\};$")
        break()
    endif()

    if(STRIPPED MATCHES "^([A-Za-z_][A-Za-z0-9_]*)[ \\t]*=[ \\t]*([0-9]+),?$")
        set(NAME "${CMAKE_MATCH_1}")
        set(VALUE "${CMAKE_MATCH_2}")

        list(FIND MATLAB_RESERVED_WORDS "${NAME}" WORD_INDEX)
        list(FIND MATLAB_METHOD_NAMES "${NAME}" METHOD_INDEX)
        if(NOT WORD_INDEX EQUAL -1 OR NOT METHOD_INDEX EQUAL -1)
            set(NAME "${NAME}_op")
        endif()

        string(FORMAT "%08d" VALUE_KEY "${VALUE}")
        list(APPEND ENTRIES "${VALUE_KEY}|${NAME}|${VALUE}")
    endif()
endforeach()

if(NOT IN_ENUM)
    message(FATAL_ERROR "Could not find enum class Operation in ${HEADER_FILE}")
endif()
if(ENTRIES STREQUAL "")
    message(FATAL_ERROR "No enum entries were parsed from ${HEADER_FILE}")
endif()

list(SORT ENTRIES)

set(MEMBERS "")
foreach(ENTRY IN LISTS ENTRIES)
    string(REPLACE "|" ";" PARTS "${ENTRY}")
    list(GET PARTS 1 NAME)
    list(GET PARTS 2 VALUE)
    string(APPEND MEMBERS "        ${NAME} (${VALUE})\n")
endforeach()

set(MATLAB_FILE "classdef OpCode < uint32\n")
string(APPEND MATLAB_FILE "% sig.OpCode  Integer opcodes for signal network node operations.\n")
string(APPEND MATLAB_FILE "%\n")
string(APPEND MATLAB_FILE "% AUTO-GENERATED - do not edit by hand.\n")
string(APPEND MATLAB_FILE "% Source:    Signals/transferer.h  (enum class Operation)\n")
string(APPEND MATLAB_FILE "% Generator: scripts/gen_opcodes.cmake\n")
string(APPEND MATLAB_FILE "%\n")
string(APPEND MATLAB_FILE "% This file is rebuilt as a CMake build dependency of signalsproxy,\n")
string(APPEND MATLAB_FILE "% ensuring the MATLAB enum always matches the C++ enum.\n")
string(APPEND MATLAB_FILE "% To regenerate manually from the repo root:\n")
string(APPEND MATLAB_FILE "%   cmake -DHEADER_FILE=Signals/transferer.h -DOUTPUT_FILE=matlab/+sig/OpCode.m -P scripts/gen_opcodes.cmake\n")
string(APPEND MATLAB_FILE "%\n")
string(APPEND MATLAB_FILE "% Usage:\n")
string(APPEND MATLAB_FILE "%   net.addNode(src, sig.OpCode.map_op,  false, fn)\n")
string(APPEND MATLAB_FILE "%   net.addNode([],  sig.OpCode.nop,     false)\n")
string(APPEND MATLAB_FILE "%\n")
string(APPEND MATLAB_FILE "% See also sig.Net.addNode, sig.node.Signal, Signals/transferer.h\n")
string(APPEND MATLAB_FILE "\n")
string(APPEND MATLAB_FILE "    enumeration\n")
string(APPEND MATLAB_FILE "${MEMBERS}")
string(APPEND MATLAB_FILE "    end\n")
string(APPEND MATLAB_FILE "end\n")

file(WRITE "${OUTPUT_FILE}" "${MATLAB_FILE}")
message(STATUS "[gen_opcodes] Wrote ${OUTPUT_FILE}")
