function [val, valset] = schedule(values, states, ~)
% sig.transfer.schedule  Creates a schedule packet with value and delay.
%
% [val, valset] = schedule(values, states)
%   Combines the 'what' input value with the 'delay' input to create a
%   schedule packet for delayed posting.
%   Assumes two inputs in order: [what, delay].
%
%   values — 1×2 cell: {what_value, delay_value}
%   states — 1×2 int8: state flags (-1=unset, 0=current, 1=new-working)
%
% See also sig.Signal/delay, sig.OriginSignal/delayedPost

    % both inputs must be set but what_value must have a new working value
    % (delay can be current or new working)
    if states(1) < 1 || states(2) < 0
        val = [];
        valset = false;
    else
        val = values;  % create schedule packet
        valset = true;
    end
end
