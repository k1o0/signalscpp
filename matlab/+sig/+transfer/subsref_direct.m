function [val, valset] = subsref_direct(values, states, subs)
% sig.transfer.subsref_direct  Index into an array signal with direct subscripts
%
% [val, valset] = subsref_direct(values, states, subs)
%   Applies subscript operations to the array in the first input using
%   subscript indices from the subs cell array. This differs from subsref
%   in that subs is passed directly rather than extracted from values,
%   allowing sig.End objects to be preserved.
%
%   The values/states arrays include: [node_value, input1, input2, ...]
%   where input1 is the array, and input2+ are signals corresponding to
%   non-sig.End subscripts only (sig.End subscripts are not in the values array).
%
%   subs — cell array containing subscript indices (can include sig.End objects)
%   values — cell array: {node_value, input1, input2, ...} where input2+ are
%            only for non-sig.End subscripts
%   states — int8 array: state flags (-1=unset, 0=current, 1=new-working)
%
% See also sig.Signal/subsref, sig.transfer.subsref

    val = []; valset = false;

    % The first element is the node's own value, skip it
    % Input 1 (the array to subscript) is at index 2

    % Check if array input is set
    if numel(values) < 2 || states(2) < 0
        return;
    end

    % We need at least one subscript index
    if isempty(subs)
        return;
    end

    % Check which subscripts correspond to values/states
    % Count how many non-sig.End subscripts we have
    numNonEndSubs = sum(cellfun(@(s) ~isa(s, 'sig.End'), subs));

    % Check if all non-sig.End signal subscripts are set
    valueIdx = 3;  % Start at index 3 (after node value and array)
    for k = 1:numel(subs)
        if ~isa(subs{k}, 'sig.End')
            if isa(subs{k}, 'sig.Signal')
                if valueIdx > numel(values) || states(valueIdx) < 0
                    return;
                end
                valueIdx = valueIdx + 1;
            elseif ~isa(subs{k}, 'sig.End')
                % Constant subscript - might be in values if it was added as a node
                if valueIdx <= numel(values) && states(valueIdx) >= 0
                    valueIdx = valueIdx + 1;
                end
            end
        end
    end

    % Fire only when ANY input (array or non-sig.End subscript) has a NEW value
    hasNewValue = states(2) == 1;  % Array is new
    for k = 3:numel(states)
        if states(k) == 1
            hasNewValue = true;
            break;
        end
    end
    if ~hasNewValue
        return;
    end

    % Get the array to subscript
    what = values{2};

    % Process subscripts: resolve sig.End objects and pull signal values
    resolvedSubs = cell(size(subs));
    valueIdx = 3;  % Start at index 3 (after node value and array)

    for k = 1:numel(subs)
        sub = subs{k};
        if isa(sub, 'sig.End')
            % Resolve sig.End based on array size
            resolvedSubs{k} = sub.resolve(what);
        elseif isa(sub, 'sig.Signal')
            % Get the signal's value from values
            if valueIdx <= numel(values)
                resolvedSubs{k} = values{valueIdx};
                valueIdx = valueIdx + 1;
            end
        else
            % Constant subscript
            resolvedSubs{k} = sub;
            % Check if this constant was added as a node
            if valueIdx <= numel(values) && states(valueIdx) >= 0
                % Use the value from the node instead
                resolvedSubs{k} = values{valueIdx};
                valueIdx = valueIdx + 1;
            end
        end
    end

    % Create subscript struct
    s = struct('type', '()', 'subs', {resolvedSubs});

    % Apply the subscript, catching out-of-bounds errors
    try
        val = subsref(what, s);
        valset = true;
    catch ex
        % Re-throw all errors to allow proper error handling
        rethrow(ex);
    end
end
