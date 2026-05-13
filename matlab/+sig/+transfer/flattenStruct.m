function [val, valset] = flattenStruct(values, states, fieldNames, template)
% sig.transfer.flattenStruct  Build a flat struct from signal-valued fields.
%
% [val, valset] = flattenStruct(values, states, fieldNames, template)
%
%   Fires when at least one signal-field input has a new working value AND
%   all signal-field inputs have at least one committed value.
%
%   values     — 1×(N+1) cell: {this_curr, field1_latest, ..., fieldN_latest}
%   states     — 1×(N+1) int8: state flags  (-1=unset, 0=current, 1=new)
%   fieldNames — 1×N cell of char: struct field names for each input
%   template   — struct with non-signal fields pre-filled; signal fields []
%
% The returned struct has all fields set: non-signal fields from template,
% signal fields from the latest input values.
%
% See also sig.Signal/flattenStruct, sig.Signal/flatten

    val = []; valset = false;
    input_states = states(2:end);           % one entry per signal field
    if any(input_states < 0); return; end   % some field never fired
    if ~any(input_states == 1); return; end % none fired this tick

    val = template;
    for fi = 1:numel(fieldNames)
        val.(fieldNames{fi}) = values{fi + 1};
    end
    valset = true;
end
