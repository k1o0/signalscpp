classdef SubscriptableSignal < sig.Signal
% sig.SubscriptableSignal  Signal supporting dot-syntax field access.
%
% Dot-subscripting a SubscriptableSignal returns a new derived signal
% whose value is the named field of the parent signal's value, updating
% whenever the parent updates.
%
%   s = net.subscriptableOrigin('params');
%   s.x = 5;               % post {x:5} to network
%   x = s.x;               % sig.SubscriptableSignal: value follows s.x
%   y = s.x.nested;        % multi-level when Deep == true
%
% Obtain via sig.Signal.subscriptable() or sig.Net.subscriptableOrigin().
%
% See also sig.SubscriptableOriginSignal, sig.Signal/subscriptable,
%          sig.Net/subscriptableOrigin

    properties
        % When true, cache derived signals so repeated s.x returns the same node
        CacheSubscripts (1,1) logical = false
    end

    properties (SetAccess = protected)
        % When true, subscript results are themselves subscriptable
        Deep (1,1) logical = false
    end

    properties (Access = private, Transient)
        % containers.Map: field name -> cached derived signal
        Subscripts
    end

    methods

        function this = SubscriptableSignal(node, deep)
        % SubscriptableSignal  Wrap node; optionally enable deep chaining.
            this = this@sig.Signal(node);
            if nargin >= 2
                this.Deep = logical(deep);
            end
            this.Subscripts = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function this = subscriptable(this)
        % subscriptable  Already subscriptable — return self unchanged.
        end

        function [varargout] = subsref(a, s)
        % subsref  Intercept dot-access to build derived signals.
        %   Known methods and properties use builtin dispatch.
        %   Unknown names create a new signal = parent.map(@(v) v.name).
        %   When CacheSubscripts is true, the derived signal is reused on
        %   repeated accesses to the same field name.
            if strcmp(s(1).type, '.')
                dotname = s(1).subs;
                % Route known methods/properties through builtin
                if ismethod(a, dotname) || isprop(a, dotname)
                    [varargout{1:nargout}] = builtin('subsref', a, s);
                    return;
                end
                % Return cached signal if available
                if a.CacheSubscripts && ~isa(dotname, 'sig.Signal') ...
                        && isKey(a.Subscripts, dotname)
                    out = a.Subscripts(dotname);
                else
                    % Build a derived signal for the subscript
                    if isa(dotname, 'sig.Signal')
                        % Dynamic field name supplied as a signal
                        subscript = a.map2(dotname, @(v, k) v.(k));
                        subscript.Node.FormatSpec    = '%s.(%s)';
                        subscript.Node.DisplayInputs = [a.Node, dotname.Node];
                    else
                        subscript = a.map( ...
                            @(v) v.(dotname), ...
                            sprintf('%%s.%s', dotname));
                        subscript.Node.DisplayInputs = a.Node;
                    end
                    isDeep = a.Deep;
                    out = subscript;
                    if isDeep
                        out = out.subscriptable();
                        out.Deep = true;
                    end
                    if a.CacheSubscripts && ~isa(dotname, 'sig.Signal')
                        a.Subscripts(dotname) = out;
                    end
                end
                if length(s) > 1
                    [varargout{1:nargout}] = subsref(out, s(2:end));
                else
                    varargout = {out};
                end
            else
                if strcmp(s(1).type, '()')
                    subs = s(1);
                    out = a.map(@(v) builtin('subsref', v, subs));
                    if length(s) > 1
                        [varargout{1:nargout}] = subsref(out, s(2:end));
                    else
                        varargout = {out};
                    end
                else
                    [varargout{1:nargout}] = builtin('subsref', a, s);
                end
            end
        end

    end

end
