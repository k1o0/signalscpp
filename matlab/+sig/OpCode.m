classdef OpCode < uint32
% sig.OpCode  Integer opcodes for signal network node operations.
%
% AUTO-GENERATED - do not edit by hand.
% Source:    Signals/transferer.h  (enum class Operation)
% Generator: scripts/gen_opcodes.ps1
%
% This file is rebuilt as a CMake PRE_BUILD step on signalsproxy,
% ensuring the MATLAB enum always matches the C++ enum.
% To regenerate manually from the repo root:
%   powershell -File scripts\gen_opcodes.ps1
%
% Usage:
%   net.addNode(src, sig.OpCode.map_op,  false, fn)
%   net.addNode([],  sig.OpCode.nop,     false)
%
% See also sig.Net.addNode, sig.node.Signal, Signals/transferer.h

    enumeration
        function_op    (0)
        plus           (1)
        minus          (2)
        mtimes         (3)
        rdivide        (4)
        mdivide        (5)
        gt             (10)
        ge             (11)
        lt             (12)
        le             (13)
        eq             (14)
        merge          (20)
        at_op          (21)
        keep_when      (22)
        latch          (23)
        skip_repeats   (24)
        select_from    (25)
        numel          (30)
        flattenstruct  (40)
        identity       (50)
        nop            (51)
        map_op         (60)
        mapn_op        (61)
        filter_op      (62)
        scan_op        (63)
    end
end