classdef TidyHandle < handle
  % TidyHandle A handle that can tidy up after itself
  %   Detailed explanation goes here
  
  properties (Hidden, SetAccess = private, Transient)
    Task
    Value
  end
  
  methods
    function this = TidyHandle(task, value)
      this.Task = task;
      if nargin > 1
        this.Value = value;
      end
    end
    
    function delete(this)
      this.Task();
      this.Task = []; % this is propbably overkill
      this.Value = [];
    end
  end
  
end

