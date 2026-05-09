classdef Signal < sig.Signal
% sig.node.Signal  Concrete reactive signal backed by a network node.
%
% Instances are created by sig.Net.addNode() — do not construct directly.
% All combinators (map, filter, scan, etc.) return new sig.node.Signal
% instances that are wired into the same reactive network.
%
% PROPERTIES (Dependent)
%   Id           — node id within the network (read-only)
%   CurrentValue — committed value after the last apply()
%   WorkingValue — in-transaction value ([] outside a transact)
%   InputIds     — row vector of upstream node ids
%
% See also sig.Signal, sig.node.OriginSignal, sig.Net

    properties (Hidden, SetAccess = private)
        % The underlying MEX-side node proxy.
        Node
    end

    properties (Dependent)
        Id
        CurrentValue
        WorkingValue
        InputIds
    end

    properties (Access = private)
        Net_   % parent sig.Net (value-class copy — Proxy is a shared handle)
    end

    methods

        function obj = Signal(proxyId, net)
        % Signal  Wrap a C++ NodeProxy and record the owning network.
        %   Called internally by sig.Net.addNode and sig.Net.origin.
            obj.Node = sig.Node(proxyId, net);
            obj.Net_ = net;
        end

        % -----------------------------------------------------------------
        % Dependent property getters
        % -----------------------------------------------------------------

        function v = get.Id(obj)
            v = obj.Node.Id;
        end

        function v = get.CurrentValue(obj)
            v = obj.Node.CurrentValue;
        end

        function v = get.WorkingValue(obj)
            v = obj.Node.WorkingValue;
        end

        function ids = get.InputIds(obj)
            ids = obj.Node.InputIds;
        end

        % -----------------------------------------------------------------
        % Core combinators implementing the sig.Signal abstract interface
        % -----------------------------------------------------------------

        function out = map(obj, fn)
        % map  New signal = fn(this_value) on every update.
            out = obj.Net_.addNode(obj, 60, false, fn);
        end

        function out = map2(sig1, sig2, f)
        % map2  New signal = f(sig1, sig2) whenever either fires.
        %   Either sig1 or sig2 may be a constant — it is wrapped
        %   automatically as a pre-posted origin node.
        %   Note: MATLAB may dispatch here with sig1 as a numeric constant
        %   (e.g., 3 + signal) due to class-precedence rules; this is
        %   handled explicitly.
            if isa(sig1, 'sig.node.Signal')
                net = sig1.Net_;
            elseif isa(sig2, 'sig.node.Signal')
                net = sig2.Net_;
            else
                error('sig:noNet', ...
                    'map2: neither argument is a sig.node.Signal.');
            end
            sig1 = sig.node.Signal.wrapConst_(net, sig1);
            sig2 = sig.node.Signal.wrapConst_(net, sig2);
            out  = net.addNode({sig1, sig2}, 61, false, f);
        end

        function varargout = mapn(varargin)
        % mapn  New signal(s) by applying fn to N input signals/constants.
        %   Call as:  out = s1.mapn(s2, ..., sN, fn)
        %          or: out = mapn(s1, s2, ..., sN, fn)   (MATLAB dispatch)
        %   fn is always the last argument; preceding args are inputs.
        %   Constants among the inputs are wrapped as origin nodes.
            fn     = varargin{end};
            inputs = varargin(1:end-1);
            net    = sig.node.Signal.findNet_(inputs{:});
            for k = 1:numel(inputs)
                inputs{k} = sig.node.Signal.wrapConst_(net, inputs{k});
            end
            varargout{1} = net.addNode(inputs, 61, false, fn);
        end

        function out = filter(obj, fn)
        % filter  Pass values through when fn(value) is truthy.
            out = obj.Net_.addNode(obj, 62, false, fn);
        end

        function out = scan(obj, fn, seed)
        % scan  Running fold: acc = fn(acc, new_value).
        %   seed — initial accumulator value, or a signal that resets it.
        %   If seed is a signal it is used directly as the seed node.
        %   If seed is a constant it is wrapped as a pre-posted origin.
            if isa(seed, 'sig.Signal') || isa(seed, 'sig.Node')
                seedRef = seed;
            else
                seedRef = obj.Net_.origin(seed);
            end
            out = obj.Net_.addNode({obj, seedRef}, 63, false, fn);
        end

        function out = numel(obj)
        % numel  New signal whose value is numel(this_value).
        %   Overrides sig.Signal.numel to use the dedicated C++ opcode.
            out = obj.Net_.addNode(obj, 30, false);
        end

        function out = identity(obj)
        % identity  New signal that mirrors this signal (ordering guarantee).
            out = obj.Net_.addNode(obj, 50, false);
        end

        % -----------------------------------------------------------------
        % Stubs for ops not yet backed by C++ opcodes
        % -----------------------------------------------------------------

        function out = at(obj, when) %#ok<INUSD>
            error('sig:notImplemented', 'at() is not yet implemented.');
        end

        function out = keepWhen(obj, when) %#ok<INUSD>
            error('sig:notImplemented', 'keepWhen() is not yet implemented.');
        end

        function out = to(obj, b) %#ok<INUSD>
            error('sig:notImplemented', 'to() is not yet implemented.');
        end

        function out = setTrigger(obj, release) %#ok<INUSD>
            error('sig:notImplemented', 'setTrigger() is not yet implemented.');
        end

        function out = setEpochTrigger(obj, t, x, threshold) %#ok<INUSD>
            error('sig:notImplemented', 'setEpochTrigger() is not yet implemented.');
        end

        function out = skipRepeats(obj)
            error('sig:notImplemented', 'skipRepeats() is not yet implemented.');
        end

        function out = delta(obj)
            error('sig:notImplemented', 'delta() is not yet implemented.');
        end

        function out = delay(obj, period) %#ok<INUSD>
            error('sig:notImplemented', 'delay() is not yet implemented.');
        end

        function out = lag(obj, n) %#ok<INUSD>
            error('sig:notImplemented', 'lag() is not yet implemented.');
        end

        function out = bufferUpTo(obj, nSamples) %#ok<INUSD>
            error('sig:notImplemented', 'bufferUpTo() is not yet implemented.');
        end

        function out = buffer(obj, nSamples) %#ok<INUSD>
            error('sig:notImplemented', 'buffer() is not yet implemented.');
        end

        function out = merge(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'merge() is not yet implemented.');
        end

        function out = selectFrom(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'selectFrom() is not yet implemented.');
        end

        function out = indexOfFirst(obj, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'indexOfFirst() is not yet implemented.');
        end

        function out = cond(obj, value1, varargin) %#ok<INUSD>
            error('sig:notImplemented', 'cond() is not yet implemented.');
        end

        function h = onValue(obj, f) %#ok<INUSD>
            error('sig:notImplemented', 'onValue() is not yet implemented.');
        end

        function h = output(obj)
            error('sig:notImplemented', 'output() is not yet implemented.');
        end

    end

    % -----------------------------------------------------------------
    % Private static helpers
    % -----------------------------------------------------------------
    methods (Static, Access = private)

        function net = findNet_(varargin)
        % findNet_  Return the Net_ from the first sig.node.Signal argument.
            for k = 1:nargin
                if isa(varargin{k}, 'sig.node.Signal')
                    net = varargin{k}.Net_;
                    return;
                end
            end
            error('sig:noNet', 'No sig.node.Signal found in arguments.');
        end

        function ref = wrapConst_(net, val)
        % wrapConst_  Return val unchanged if it is a signal/node; otherwise
        %   wrap it as a pre-posted origin node for use as a network input.
            if isa(val, 'sig.Signal') || isa(val, 'sig.Node')
                ref = val;
            else
                ref = net.origin(val);
            end
        end

    end

end
