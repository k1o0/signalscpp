classdef OpCode < uint32
% sig.OpCode  Integer opcodes for signal network node operations.
%
% AUTO-GENERATED - do not edit by hand.
% Source:    Signals/transferer.h  (enum class Operation)
% Generator: scripts/gen_opcodes.cmake
%
% This file is rebuilt as a CMake build dependency of signalsproxy,
% ensuring the MATLAB enum always matches the C++ enum.
% To regenerate manually from the repo root:
%   cmake -DHEADER_FILE=Signals/transferer.h -DOUTPUT_FILE=matlab/+sig/OpCode.m -P scripts/gen_opcodes.cmake
%
% Usage:
%   net.addNode(src, sig.OpCode.map_op,  false, fn)
%   net.addNode([],  sig.OpCode.nop,     false)
%
% See also sig.Net.addNode, sig.node.Signal, Signals/transferer.h

    enumeration
        function_op (0)
        plus_op (1)
        minus_op (2)
        mtimes_op (3)
        rdivide_op (4)
        mdivide (5)
        gt_op (10)
        ge_op (11)
        lt_op (12)
        le_op (13)
        eq_op (14)
        merge (20)
        at_op (21)
        keep_when (22)
        latch (23)
        skip_repeats (24)
        select_from (25)
        index_of_first (26)
        buffer_up_to (27)
        numel_op (30)
        flatten_struct_op (40)
        flatten_op (41)
        identity (50)
        nop (51)
        map_op (60)
        mapn_op (61)
        filter_op (62)
        scan_op (63)
    end
end
