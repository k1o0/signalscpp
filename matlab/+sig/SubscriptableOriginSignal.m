classdef SubscriptableOriginSignal < sig.SubscriptableSignal & sig.OriginSignal
% sig.SubscriptableOriginSignal  Origin signal with dot-syntax r/w access.
%
% Created by sig.Net.subscriptableOrigin().
%
% Dot-subscript READING creates a derived signal (see SubscriptableSignal):
%   x = s.fieldName    % new signal: value follows s_value.fieldName
%
% Dot-subscript WRITING posts a struct update to the network:
%   s.fieldName = val  % posts current struct with fieldName updated to val
%
% Multi-level read chains are supported (Deep = true):
%   y = s.a.b          % value follows s_value.a.b
%
% Multi-level write (e.g. s.a.b = v) is not supported.
%
% See also sig.SubscriptableSignal, sig.OriginSignal, sig.Net/subscriptableOrigin

    methods

        function this = SubscriptableOriginSignal(node)
        % SubscriptableOriginSignal  Wrap node; enable deep subscripting.
            this = this@sig.SubscriptableSignal(node);
            this = this@sig.OriginSignal(node);
            this.Deep = true;
        end

        function a = subsasgn(a, s, b)
        % subsasgn  Dot-assignment posts a struct field update to the network.
        %   a.fieldName = b  — read current struct value, set fieldName=b, post.
        %   Reserved method/property names use builtin assignment instead.
            if isa(a, 'sig.SubscriptableOriginSignal') && strcmp(s(1).type, '.')
                if ismethod(a, s(1).subs) || isprop(a, s(1).subs)
                    a = builtin('subsasgn', a, s, b);
                    return;
                end
                assert(numel(s) == 1, 'sig:SubscriptableOriginSignal:deepAssign', ...
                    'Multi-level subscripted assignment is not supported.');
                curr = a.Node.Value;
                if isempty(curr); curr = struct(); end
                newValue = builtin('subsasgn', curr, s(1), b);
                a.Node.Net.post(a.Node, newValue);
            else
                a = builtin('subsasgn', a, s, b);
            end
        end

    end

end
