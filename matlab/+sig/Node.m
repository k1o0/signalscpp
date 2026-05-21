classdef Node < handle
% sig.Node  MEX shim around a single node inside a sig.Net.
%
% sig.Node is the low-level handle that carries the node's numeric id,
% its latest value, and its list of upstream input ids.  Every sig.Signal
% owns exactly one sig.Node.
%
% sig.Node also provides the from() method, which is the canonical way for
% combinator methods to coerce mixed lists of signals, nodes, and plain
% data values into a uniform cell array of sig.Node objects.
%
% PROPERTIES
%   Id       (double, read-only) node id within the network
%   Net      (sig.Net, read-only) parent network
%   Value    (Dependent) latest value: working during a transact, else the
%             last committed value; [] if never set
%   Inpus (Dependent) array of upstream Nodes
%
% METHODS
%   nodes = n.from(arg1, arg2, ...)
%     Coerce each argument to a sig.Node in this node's network.
%     - sig.Node   : returned as-is (same network asserted)
%     - sig.Signal : its .Node property is extracted (same network asserted)
%     - anything else: wrapped in a constant node via net.rootNode(v)
%     Returns a cell array {n1, n2, ...} with one entry per argument.
%
% See also sig.Signal, sig.OriginSignal, sig.Net

   properties
      % An optional format string to construct name from inputs
      FormatSpec (1,1) string

      % The nodes (and their ordering) which are presented as inputs, e.g.
      % used in formatting the name of the node, or in a GUI
      DisplayInputs sig.Node
   end

    properties (SetAccess = immutable)
        Id  (1,1) double       % node id within the network
        Net sig.Net            % sig.Net — parent network (value copy; proxy is shared)

        % Array of input nodes
        Inputs sig.Node
    end

    properties (Transient)
        % For storing handles to Node update callbacks
        Listeners TidyHandle
    end

    properties (Dependent)
        % The name of the node
        Name (1,1) string

        % Latest node value or [] if never set
        Value
    end

    properties (Access = private)
        % Handle to the C++ NodeProxy
        Proxy libmexclass.proxy.Proxy

        % Name to display instead of using format spec
        NameOverride (1,1) string
    end


    methods

        function obj = Node(proxyId, net, inputs)
        % Node  Wrap an existing C++ NodeProxy.
        %   proxyId — uint64 proxy ID returned by NetworkProxy::AddNode
        %   net     — parent sig.Net
        %   inputs  — array of input nodes
            obj.Proxy = libmexclass.proxy.Proxy( ...
                "Name", "sig.NodeProxy", ...
                "ID",   libmexclass.proxy.Identifier(proxyId));
            obj.Id  = obj.Proxy.GetId();
            obj.Net = net;
            % Assign node inputs
            if nargin < 3; inputs = sig.Node.empty(1, 0); end
            assert(all(arrayfun(@(x) isequal(x.Net, net), inputs)), ...
                'sig:Node:wrongNet', 'Not all input nodes belong to the same network.')
            assert(all(obj.Proxy.GetInputIds() == [inputs.Id]), ...
                'sig:Node:inputMismatch', 'Input node IDs do not match the C++ graph.')
            obj.Inputs = inputs;
            obj.DisplayInputs = obj.Inputs;
        end

        % -----------------------------------------------------------------
        % Dependent property getters
        % -----------------------------------------------------------------

        function v = get.Name(this)
            if this.NameOverride ~= ""
                v = this.NameOverride;
            elseif this.FormatSpec == ""
                v = sprintf("n%i", this.Id);
            else
                childNames = sig.Node.names(this.DisplayInputs);
                v = sprintf(this.FormatSpec, childNames{:});
            end
        end

        function set.Name(this, v)
            this.NameOverride = string(v);
        end

        function v = get.Value(obj)
            v = obj.Proxy.GetValue();
        end

    end

    methods (Static)

        function [nodes, net] = from(varargin)
            % FROM Returns an array of nodes from a set of inputs
            %
            %   The inputs may contain signals, nodes, and/or values of
            %   another type.  All signals/nodes must be part of the same
            %   parent network.  If a source value is not a signal, a root
            %   node is created to hold that value.  This is useful for
            %   deriving a new node, whose inputs are derived from one or
            %   more other signals.
            %
            %   Each argument may be:
            %     sig.Node   — returned as-is; network identity is asserted.
            %     sig.Signal — its Node is extracted; network identity is asserted.
            %     scalar data — posted to a fresh constant node via net.rootNode().
            %
            %   Returns a 1×N array of sig.Node handles, one per argument,
            %   and the shared sig.Net instance.
            %
            % See also sig.Net.rootNode
            nodes = sig.Node.empty(0, numel(varargin));

            isSignal = cellfun(@(s) isa(s, 'sig.Signal') || isa(s, 'sig.Node'), varargin);
            try
                sgl = varargin{find(isSignal, 1)};
                if isa(sgl, 'sig.Signal')
                    net = sgl.Node.Net;
                else
                    net = sgl.Net;
                end
            catch
                error('sig:node:noNet', 'No network provided')
            end

            % Now coerce nodes from each input
            for k = 1:numel(varargin)
                v = varargin{k};
                if isa(v, 'sig.Node')
                    assert(v.Net.Id == net.Id, 'sig:wrongNet', ...
                        'sig.Node.from: Node belongs to a different network.');
                    nodes(k) = v;
                elseif isa(v, 'sig.Signal')
                    assert(v.Node.Net.Id == net.Id, 'sig:wrongNet', ...
                        'sig.Node.from: Signal belongs to a different network.');
                    nodes(k) = v.Node;
                else
                    nodes(k) = net.rootNode(v);
                end
            end
        end

        function id = idOf(v)
        % idOf  Return the node ID (double) if v is a sig.Signal, else -1.
        %   Called from C++ (via feval) by the flatten_op callable to determine
        %   whether the director value is a Signal or a plain MATLAB value.
            if isa(v, 'sig.Signal')
                id = double(v.Node.Id);
            else
                id = -1;
            end
        end

        function [fieldNames, nodeIds, template] = flattenInfo(blueprint)
        % flattenInfo  Extract signal-field metadata from a struct value.
        %   Called from C++ (via feval) by the flatten_struct_op callable when
        %   the blueprint signal fires with a new struct value.
        %
        %   Returns:
        %     fieldNames — 1×N cell: char names (scalar struct) or {name,idx} cells (struct array)
        %     nodeIds    — 1×N double: node ID for each signal field
        %     template   — struct: non-signal fields filled, signal fields = []
            fieldNames = {};
            nodeIds    = double.empty(1, 0);
            template   = struct();
            if ~isstruct(blueprint); return; end
            fn = fieldnames(blueprint);
            n_elems = numel(blueprint);
            template = blueprint;
            for ei = 1:n_elems
                for fi = 1:numel(fn)
                    val = blueprint(ei).(fn{fi});
                    if isa(val, 'sig.Signal')
                        if n_elems == 1
                            fieldNames{end+1} = fn{fi}; %#ok<AGROW>
                        else
                            fieldNames{end+1} = {fn{fi}, ei}; %#ok<AGROW>
                        end
                        nodeIds(end+1) = double(val.Node.Id); %#ok<AGROW>
                        template(ei).(fn{fi}) = [];
                    end
                end
            end
        end

        function s = fillStructFields(template, fieldNames, varargin)
        % fillStructFields  Fill signal-valued fields into a template struct.
        %   Called from C++ (via feval) by the flatten_struct_op callable to
        %   assemble the output struct from the latest field-signal values.
        %
        %   s = fillStructFields(template, fieldNames, val1, val2, ...)
        %   fieldNames elements are either char (scalar struct) or {name,idx} cell (array).
            s = template;
            for i = 1:numel(fieldNames)
                key = fieldNames{i};
                if ischar(key)
                    s.(key) = varargin{i};
                else
                    s(key{2}).(key{1}) = varargin{i};
                end
            end
        end

        function n = names(nodes)
        %names  Return the Name of each node as a cell array of strings.
        %
        %   n = sig.Node.names(nodes)
        %
        %   Used by get.Name to expand DisplayInputs names into a cell array
        %   suitable for sprintf.  A static method is required because MATLAB
        %   does not permit the shorthand [array.DependentProp] syntax inside a
        %   Dependent property getter of the same class.
        %
        %   Inputs:
        %     nodes (sig.Node) - array of nodes whose names to collect
        %
        %   Output:
        %     n (1×N string) - string array, one entry per node
        %
        %   Example:
        %     childNames = sig.Node.names(this.DisplayInputs);
        %     label = sprintf('%s + %s', childNames{:});
        %
        %   See also sig.Node.get.Name
            n = [nodes.Name];
        end

    end
end

