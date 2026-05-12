classdef Signals_methods_profile < matlab.perftest.TestCase
% Performance profiling for filter / map / mapn signal updates.
%
%   FILTER (4 conditions):
%     filter_matlab_basic   — function_op + scalar double
%     filter_matlab_complex — function_op + 100×100 double
%     filter_cpp_basic      — filter_op   + scalar double
%     filter_cpp_complex    — filter_op   + 100×100 double
%
%   MAP (4 conditions):
%     map_matlab_basic   — function_op + scalar double
%     map_matlab_complex — function_op + 100×100 double
%     map_cpp_basic      — map_op      + scalar double
%     map_cpp_complex    — map_op      + 100×100 double
%
%   MAPN (4 conditions):
%     mapn_matlab_basic   — function_op + two scalar doubles
%     mapn_matlab_complex — function_op + two 100×100 doubles
%     mapn_cpp_basic      — mapn_op     + two scalar doubles
%     mapn_cpp_complex    — mapn_op     + two 100×100 doubles
%
%   Predicate for filter: @(x) ~isempty(x) — always returns scalar true.
%
%   Run:
%     results = runperf('matlab/tests/Signals_methods_profile.m');

    properties
        % MATLAB transfer mode
        netM sig.Net

        % filter
        srcM_flt_B  sig.OriginSignal
        srcM_flt_C  sig.OriginSignal
        fltM_B      sig.Signal
        fltM_C      sig.Signal

        % map
        srcM_map_B  sig.OriginSignal
        srcM_map_C  sig.OriginSignal
        mapM_B      sig.Signal
        mapM_C      sig.Signal

        % mapn
        srcM_mapnA_B sig.OriginSignal
        srcM_mapnB_B sig.OriginSignal
        srcM_mapnA_C sig.OriginSignal
        srcM_mapnB_C sig.OriginSignal
        mapnM_B      sig.Signal
        mapnM_C      sig.Signal

        % C++ transfer mode
        netC sig.Net

        % filter
        srcC_flt_B  sig.OriginSignal
        srcC_flt_C  sig.OriginSignal
        fltC_B      sig.Signal
        fltC_C      sig.Signal

        % map
        srcC_map_B  sig.OriginSignal
        srcC_map_C  sig.OriginSignal
        mapC_B      sig.Signal
        mapC_C      sig.Signal

        % mapn
        srcC_mapnA_B sig.OriginSignal
        srcC_mapnB_B sig.OriginSignal
        srcC_mapnA_C sig.OriginSignal
        srcC_mapnB_C sig.OriginSignal
        mapnC_B      sig.Signal
        mapnC_C      sig.Signal
    end

    properties (Constant)
        BasicVal   = 1.0
        ComplexVal = rand(100, 100) + 1  % all elements > 0
    end

    % -----------------------------------------------------------------------
    % Class-level setup / teardown
    % -----------------------------------------------------------------------

    methods (TestClassSetup)
        function buildNetworks(testCase)
            addSignalsPaths();
            add_fn = @(x) x + 1;          % map function — returns same type
            sum_fn = @(a, b) a + b;       % mapn function

            % ── MATLAB transfer mode ──────────────────────────────────────
            testCase.netM = sig.Net;
            testCase.netM.TransferMode = 'matlab';

            testCase.srcM_flt_B  = testCase.netM.origin();
            testCase.srcM_flt_C  = testCase.netM.origin();
            testCase.fltM_B      = testCase.srcM_flt_B.filter(@(x) ~isempty(x));
            testCase.fltM_C      = testCase.srcM_flt_C.filter(@(x) ~isempty(x));

            testCase.srcM_map_B  = testCase.netM.origin();
            testCase.srcM_map_C  = testCase.netM.origin();
            testCase.mapM_B      = testCase.srcM_map_B.map(add_fn);
            testCase.mapM_C      = testCase.srcM_map_C.map(add_fn);

            testCase.srcM_mapnA_B = testCase.netM.origin();
            testCase.srcM_mapnB_B = testCase.netM.origin();
            testCase.srcM_mapnA_C = testCase.netM.origin();
            testCase.srcM_mapnB_C = testCase.netM.origin();
            % Prime B inputs so mapn fires on every tick of A
            testCase.srcM_mapnB_B.post(testCase.BasicVal);
            testCase.srcM_mapnB_C.post(testCase.ComplexVal);
            testCase.mapnM_B = testCase.srcM_mapnA_B.mapn(testCase.srcM_mapnB_B, sum_fn);
            testCase.mapnM_C = testCase.srcM_mapnA_C.mapn(testCase.srcM_mapnB_C, sum_fn);

            % ── C++ transfer mode ─────────────────────────────────────────
            testCase.netC = sig.Net;
            testCase.netC.TransferMode = 'cpp';

            testCase.srcC_flt_B  = testCase.netC.origin();
            testCase.srcC_flt_C  = testCase.netC.origin();
            testCase.fltC_B      = testCase.srcC_flt_B.filter(@(x) ~isempty(x));
            testCase.fltC_C      = testCase.srcC_flt_C.filter(@(x) ~isempty(x));

            testCase.srcC_map_B  = testCase.netC.origin();
            testCase.srcC_map_C  = testCase.netC.origin();
            testCase.mapC_B      = testCase.srcC_map_B.map(add_fn);
            testCase.mapC_C      = testCase.srcC_map_C.map(add_fn);

            testCase.srcC_mapnA_B = testCase.netC.origin();
            testCase.srcC_mapnB_B = testCase.netC.origin();
            testCase.srcC_mapnA_C = testCase.netC.origin();
            testCase.srcC_mapnB_C = testCase.netC.origin();
            testCase.srcC_mapnB_B.post(testCase.BasicVal);
            testCase.srcC_mapnB_C.post(testCase.ComplexVal);
            testCase.mapnC_B = testCase.srcC_mapnA_B.mapn(testCase.srcC_mapnB_B, sum_fn);
            testCase.mapnC_C = testCase.srcC_mapnA_C.mapn(testCase.srcC_mapnB_C, sum_fn);

            testCase.addTeardown(@() delete(testCase.netM));
            testCase.addTeardown(@() delete(testCase.netC));
        end
    end

    % -----------------------------------------------------------------------
    % filter tests
    % -----------------------------------------------------------------------

    methods (Test)

        function test_filter_matlab_basic(testCase)
            src = testCase.srcM_flt_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_filter_matlab_complex(testCase)
            src = testCase.srcM_flt_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_filter_cpp_basic(testCase)
            src = testCase.srcC_flt_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_filter_cpp_complex(testCase)
            src = testCase.srcC_flt_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

    end

    % -----------------------------------------------------------------------
    % map tests
    % -----------------------------------------------------------------------

    methods (Test)

        function test_map_matlab_basic(testCase)
            src = testCase.srcM_map_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_map_matlab_complex(testCase)
            src = testCase.srcM_map_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_map_cpp_basic(testCase)
            src = testCase.srcC_map_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_map_cpp_complex(testCase)
            src = testCase.srcC_map_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

    end

    % -----------------------------------------------------------------------
    % mapn tests
    % -----------------------------------------------------------------------

    methods (Test)

        function test_mapn_matlab_basic(testCase)
            src = testCase.srcM_mapnA_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_mapn_matlab_complex(testCase)
            src = testCase.srcM_mapnA_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_mapn_cpp_basic(testCase)
            src = testCase.srcC_mapnA_B;  v = testCase.BasicVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

        function test_mapn_cpp_complex(testCase)
            src = testCase.srcC_mapnA_C;  v = testCase.ComplexVal;
            testCase.startMeasuring(); src.post(v); testCase.stopMeasuring();
        end

    end
end
