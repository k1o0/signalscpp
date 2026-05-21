function [val, valset] = subsref(values, states, ~)
% sig.transfer.subsref  Index into an array signal
%
% [val, valset] = subsref(values, states)
%   Applies subscript operations to the array in the first input using
%   subscript indices from the remaining inputs.
%   The values/states arrays include: [node_value, input1, input2, ...]
%   We only care about the inputs, not the node's own value (element 1).
%
%   values — cell array: {node_value, input1, input2, ...}
%   states — int8 array: state flags (-1=unset, 0=current, 1=new-working)
%
% See also sig.Signal/subsref

    val = []; valset = false;

    % The first element is the node's own value, skip it
    % Input 1 (the array to subscript) is at index 2
    % Inputs 2+ (the subscript indices) are at indices 3+

    % Check if array input is set
    if numel(values) < 2 || states(2) < 0
        return;
    end

    % We need at least one subscript index
    if numel(values) < 3
        return;
    end

    % Check if any subscript input is unset
    for k = 3:numel(states)
        if states(k) < 0
            return;
        end
    end

    % Fire only when ANY input (array or subscript) has a NEW value
    if ~any(states(2:end) == 1)
        return;
    end

    % Get the array to subscript
    what = values{2};

    % Get subscript indices (skip first two: node value and array)
    subs = values(3:end);

    % Build a subscript struct for use with builtin subsref
    % Handle sig.End objects by resolving them based on array size
    resolvedSubs = cell(size(subs));
    for k = 1:numel(subs)
        sub = subs{k};
        % Handle sig.End expressions
        if isa(sub, 'sig.End')
            resolvedSubs{k} = sub.resolve(what);
        else
            resolvedSubs{k} = sub;
        end
    end

    % Create subscript struct
    s = struct('type', '()', 'subs', {resolvedSubs});

    % Apply the subscript
    try
        val = subsref(what, s);
        valset = true;
    catch ex
        % Re-throw the error to allow proper error handling
        rethrow(ex);
    end
end





