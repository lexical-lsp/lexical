defmodule Lexical.Ast.Analysis.Analyzer do
  @moduledoc false

  alias __MODULE__
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Module.Loader
  alias Sourceror.Zipper

  @scope_id :_scope_id

  @block_keywords [:do, :else, :rescue, :catch, :after]
  @clauses [:->]

  defmodule Alias do
    defstruct [:module, :as, :line]

    @type t :: %Alias{}

    def new(module, as, line) when is_list(module) and is_atom(as) and line > 0 do
      %Alias{module: module, as: as, line: line}
    end

    def to_module(%Alias{} = alias) do
      Module.concat(alias.module)
    end
  end

  defmodule Import do
    alias Lexical.Ast.Analysis.Analyzer.Scope
    alias Lexical.ProcessCache

    defstruct module: nil, selector: :all, line: nil
    @type function_name :: atom()
    @type function_arity :: {function_name(), arity()}
    @type selector ::
            :functions | :macros | [only: [function_arity()]] | [except: [function_arity()]]
    @type t :: %{
            module: module(),
            selector: selector(),
            line: non_neg_integer()
          }
    def new(module, line) do
      %__MODULE__{module: module, line: line}
    end

    def new(module, selector, line) do
      %__MODULE__{module: module, selector: expand_selector(selector), line: line}
    end

    def apply_to_scope(%__MODULE__{} = import, current_scope, %MapSet{} = current_imports) do
      import_module = Scope.resolve_alias_at(current_scope, import.module, import.line)

      functions = mfas_for(import_module, :functions)
      macros = mfas_for(import_module, :macros)

      case import.selector do
        :all ->
          current_imports
          |> remove_module_imports(import_module)
          |> MapSet.union(functions)
          |> MapSet.union(macros)

        [only: :functions] ->
          current_imports
          |> remove_module_imports(import_module)
          |> MapSet.union(functions)

        [only: :macros] ->
          current_imports
          |> remove_module_imports(import_module)
          |> MapSet.union(macros)

        [only: fa_list] ->
          fa_mapset = function_and_arity_to_mfa(import_module, fa_list)

          current_imports
          |> remove_module_imports(import_module)
          |> MapSet.union(fa_mapset)

        [except: fa_list] ->
          # This one is a little tricky. Imports using except have two cases.
          # In the first case, if the module hasn't been previously imported, we
          # collect all the functions in the current module and remove the ones in the
          # except clause.
          # If the module has been previously imported, we just remove the functions from
          # the except clause from those that have been previously imported.
          # See: https://hexdocs.pm/elixir/1.13.0/Kernel.SpecialForms.html#import/2-selector

          fa_mapset = function_and_arity_to_mfa(import_module, fa_list)

          current_imports =
            if already_imported?(current_imports, import_module) do
              MapSet.difference(current_imports, fa_mapset)
            else
              current_imports
              |> MapSet.union(functions)
              |> MapSet.union(macros)
            end

          MapSet.difference(current_imports, fa_mapset)
      end
    end

    defp expand_selector(selectors) do
      selectors =
        Enum.reduce(selectors, [], fn
          {{:__block__, _, [type]}, {:__block__, _, [selector]}}, acc
          when type in [:only, :except] ->
            expanded =
              case selector do
                :functions ->
                  :functions

                :macros ->
                  :macros

                keyword when is_list(keyword) ->
                  Enum.map(keyword, fn
                    {{:__block__, _, [function_name]}, {:__block__, _, [arity]}} ->
                      {function_name, arity}
                  end)
              end

            [{type, expanded} | acc]

          _, acc ->
            acc
        end)

      if selectors == [] do
        :all
      else
        selectors
      end
    end

    defp remove_module_imports(%MapSet{} = current_imports, imported_module) do
      current_imports
      |> Enum.reject(&match?({^imported_module, _, _}, &1))
      |> MapSet.new()
    end

    defp already_imported?(%MapSet{} = current_imports, imported_module) do
      Enum.any?(current_imports, &match?({^imported_module, _, _}, &1))
    end

    defp function_and_arity_to_mfa(current_module, fa_list) when is_list(fa_list) do
      MapSet.new(fa_list, fn {function, arity} -> {current_module, function, arity} end)
    end

    defp mfas_for(current_module, type) do
      if Loader.ensure_loaded?(current_module) do
        fa_list = function_and_arities_for_module(current_module, type)

        function_and_arity_to_mfa(current_module, fa_list)
      else
        MapSet.new()
      end
    end

    defp function_and_arities_for_module(module, type) do
      ProcessCache.trans({module, :info, type}, fn ->
        type
        |> module.__info__()
        |> Enum.reject(fn {name, _arity} ->
          name |> Atom.to_string() |> String.starts_with?("__")
        end)
      end)
    end
  end

  defmodule Scope do
    defstruct [
      :id,
      :range,
      module: [],
      parent_aliases: %{},
      aliases: [],
      parent_imports: MapSet.new(),
      imports: []
    ]

    @kernel_imports [
      Import.new([:Kernel], 1),
      Import.new([:Kernel, :SpecialForms], 1)
    ]

    @type import_mfa :: {module(), atom(), non_neg_integer()}
    @type scope_position :: Position.t() | :end
    @blank_doc Document.new("file:///", "", 1)

    @type t :: %__MODULE__{
            id: any(),
            range: Range.t(),
            module: [atom()],
            parent_aliases: %{atom() => atom()},
            aliases: [any()],
            parent_imports: MapSet.t(import_mfa()),
            imports: [import_mfa()]
          }

    def new(%__MODULE__{} = parent_scope, id, %Range{} = range, module \\ []) do
      parent_aliases = alias_map(parent_scope)
      parent_imports = imports(parent_scope)

      %Scope{
        id: id,
        range: range,
        module: module,
        parent_aliases: parent_aliases,
        parent_imports: parent_imports
      }
    end

    def global(%Range{} = range) do
      %Scope{id: :global, range: range}
    end

    @spec imports(t(), scope_position()) :: [import_mfa()]
    def imports(%__MODULE__{} = scope, position \\ :end) do
      end_line = end_line(scope, position)

      (@kernel_imports ++ scope.imports)
      # sorting by line ensures that imports on later lines
      # override imports on earlier lines
      |> Enum.sort_by(& &1.line)
      |> Enum.take_while(&(&1.line <= end_line))
      |> Enum.reduce(scope.parent_imports, fn %Import{} = import, current_imports ->
        Import.apply_to_scope(import, scope, current_imports)
      end)
    end

    @spec alias_map(Scope.t(), scope_position()) :: %{module() => Scope.t()}
    def alias_map(%Scope{} = scope, position \\ :end) do
      end_line = end_line(scope, position)

      scope.aliases
      # sorting by line ensures that aliases on later lines
      # override aliases on earlier lines
      |> Enum.sort_by(& &1.line)
      |> Enum.take_while(&(&1.line <= end_line))
      |> Map.new(&{&1.as, &1})
      |> Enum.into(scope.parent_aliases)
    end

    def resolve_alias_at(%__MODULE__{} = scope, module, line) do
      position = Position.new(@blank_doc, line, 1)
      aliases = alias_map(scope, position)

      case module do
        [{:__MODULE__, _, _} | suffix] ->
          current_module =
            aliases
            |> Map.get(:__MODULE__)
            |> Alias.to_module()

          Module.concat([current_module | suffix])

        [prefix | suffix] ->
          case aliases do
            %{^prefix => _} ->
              current_module =
                aliases
                |> Map.get(prefix)
                |> Alias.to_module()

              Module.concat([current_module | suffix])

            _ ->
              Module.concat(module)
          end
      end
    end

    def empty?(%Scope{aliases: [], imports: []}), do: true
    def empty?(%Scope{}), do: false

    defp end_line(%__MODULE__{} = scope, :end), do: scope.range.end.line
    defp end_line(_, %Position{} = position), do: position.line
  end

  defmodule State do
    defstruct [:document, scopes: [], visited: %{}]

    def new(%Document{} = document) do
      state = %State{document: document}

      scope =
        document
        |> global_range()
        |> Scope.global()

      push_scope(state, scope)
    end

    def current_scope(%State{scopes: [scope | _]}), do: scope

    def current_module(%State{} = state) do
      current_scope(state).module
    end

    def push_scope(%State{} = state, %Scope{} = scope) do
      Map.update!(state, :scopes, &[scope | &1])
    end

    def push_scope(%State{} = state, id, %Range{} = range, module) when is_list(module) do
      scope =
        state
        |> current_scope()
        |> Scope.new(id, range, module)

      push_scope(state, scope)
    end

    def push_scope_for(%State{} = state, quoted, %Range{} = range, module) do
      module = module || current_module(state)
      id = Analyzer.scope_id(quoted)
      push_scope(state, id, range, module)
    end

    def push_scope_for(%State{} = state, quoted, module) do
      range = get_range(quoted, state.document)
      push_scope_for(state, quoted, range, module)
    end

    def maybe_push_scope_for(%State{} = state, quoted) do
      case get_range(quoted, state.document) do
        %Range{} = range ->
          push_scope_for(state, quoted, range, nil)

        nil ->
          state
      end
    end

    def pop_scope(%State{scopes: [scope | rest]} = state) do
      %State{state | scopes: rest, visited: Map.put(state.visited, scope.id, scope)}
    end

    def push_alias(%State{} = state, %Alias{} = alias) do
      update_current_scope(state, fn %Scope{} = scope ->
        [prefix | rest] = alias.module

        alias =
          case scope.parent_aliases do
            %{^prefix => %Alias{} = existing_alias} ->
              %Alias{alias | module: existing_alias.module ++ rest}

            _ ->
              alias
          end

        Map.update!(scope, :aliases, &[alias | &1])
      end)
    end

    def push_import(%State{} = state, %Import{} = import) do
      update_current_scope(state, fn %Scope{} = scope ->
        Map.update!(scope, :imports, &[import | &1])
      end)
    end

    defp update_current_scope(%State{} = state, fun) do
      update_in(state, [Access.key(:scopes), Access.at!(0)], fn %Scope{} = scope ->
        fun.(scope)
      end)
    end

    defp get_range(quoted, %Document{} = document) do
      case Sourceror.get_range(quoted) do
        %{start: start_pos, end: end_pos} ->
          Range.new(
            Position.new(document, start_pos[:line], start_pos[:column]),
            Position.new(document, end_pos[:line], end_pos[:column])
          )

        nil ->
          nil
      end
    end

    defp global_range(%Document{} = document) do
      num_lines = Document.size(document)

      Range.new(
        Position.new(document, 1, 1),
        Position.new(document, num_lines + 1, 1)
      )
    end
  end

  @doc """
  Traverses an AST, returning a list of scopes.
  """
  def traverse(quoted, %Document{} = document) do
    quoted = preprocess(quoted)

    {_, state} =
      Macro.traverse(
        quoted,
        State.new(document),
        fn quoted, state ->
          {quoted, analyze_node(quoted, state)}
        end,
        fn quoted, state ->
          case {scope_id(quoted), State.current_scope(state)} do
            {id, %Scope{id: id}} ->
              {quoted, State.pop_scope(state)}

            _ ->
              {quoted, state}
          end
        end
      )

    unless length(state.scopes) == 1 do
      raise RuntimeError,
            "invariant not met, :scopes should only contain the global scope: #{inspect(state)}"
    end

    state
    # pop the final, global state
    |> State.pop_scope()
    |> Map.fetch!(:visited)
    |> Map.reject(fn {_id, scope} -> Scope.empty?(scope) end)
    |> correct_ranges(quoted, document)
    |> Map.values()
  end

  defp preprocess(quoted) do
    Macro.prewalk(quoted, &with_scope_id/1)
  end

  defp correct_ranges(scopes, quoted, document) do
    {_zipper, scopes} =
      quoted
      |> Zipper.zip()
      |> Zipper.traverse(scopes, fn %Zipper{node: node} = zipper, scopes ->
        id = scope_id(node)

        if scope = scopes[id] do
          {zipper, Map.put(scopes, id, maybe_correct_range(scope, zipper, document))}
        else
          {zipper, scopes}
        end
      end)

    scopes
  end

  # extend range for block pairs to either the beginning of their next
  # sibling or, if they are the last element, the end of their parent
  defp maybe_correct_range(scope, %Zipper{node: {_, _}} = zipper, %Document{} = document) do
    with %Zipper{node: sibling} <- Zipper.right(zipper),
         %{start: sibling_start} <- Sourceror.get_range(sibling) do
      new_end = Position.new(document, sibling_start[:line], sibling_start[:column])
      put_in(scope.range.end, new_end)
    else
      _ ->
        # we go up twice to get to the real parent because ast pairs
        # are always in a list
        %Zipper{node: parent} = zipper |> Zipper.up() |> Zipper.up()
        parent_end = Sourceror.get_range(parent).end
        new_end = Position.new(document, parent_end[:line], parent_end[:column])
        put_in(scope.range.end, new_end)
    end
  end

  defp maybe_correct_range(scope, _zipper, _document) do
    scope
  end

  # add a unique ID to 3-element tuples
  defp with_scope_id({_, _, _} = quoted) do
    Macro.update_meta(quoted, &Keyword.put(&1, @scope_id, make_ref()))
  end

  defp with_scope_id(quoted) do
    quoted
  end

  @doc false
  def scope_id({_, meta, _}) when is_list(meta) do
    Keyword.get(meta, @scope_id)
  end

  def scope_id({left, right}) do
    {scope_id(left), scope_id(right)}
  end

  def scope_id(list) when is_list(list) do
    Enum.map(list, &scope_id/1)
  end

  def scope_id(_) do
    nil
  end

  # defmodule Foo do
  defp analyze_node({:defmodule, meta, [{:__aliases__, _, segments} | _]} = quoted, state) do
    module =
      case State.current_module(state) do
        [] -> segments
        current_module -> reify_alias(current_module, segments)
      end

    current_module_alias = Alias.new(module, :__MODULE__, meta[:line])

    state
    # implicit alias belongs to the current scope
    |> maybe_push_implicit_alias(segments, meta[:line])
    # new __MODULE__ alias belongs to the new scope
    |> State.push_scope_for(quoted, module)
    |> State.push_alias(current_module_alias)
  end

  # alias Foo.{Bar, Baz, Buzz.Qux}
  defp analyze_node({:alias, meta, [{{:., _, [aliases, :{}]}, _, aliases_nodes}]}, state) do
    base_segments = expand_alias(aliases, state)

    Enum.reduce(aliases_nodes, state, fn {:__aliases__, _, segments}, state ->
      alias = Alias.new(base_segments ++ segments, List.last(segments), meta[:line])
      State.push_alias(state, alias)
    end)
  end

  # alias Foo
  # alias Foo.Bar
  # alias __MODULE__.Foo
  defp analyze_node({:alias, meta, [aliases]}, state) do
    case expand_alias(aliases, state) do
      [_ | _] = segments ->
        alias = Alias.new(segments, List.last(segments), meta[:line])
        State.push_alias(state, alias)

      [] ->
        state
    end
  end

  # alias Foo, as: Bar
  defp analyze_node({:alias, meta, [aliases, options]}, state) do
    with {:ok, alias_as} <- fetch_alias_as(options),
         [_ | _] = segments <- expand_alias(aliases, state) do
      alias = Alias.new(segments, alias_as, meta[:line])
      State.push_alias(state, alias)
    else
      _ ->
        analyze_node({:alias, meta, [aliases]}, state)
    end
  end

  # import with selector import MyModule, only: :functions
  defp analyze_node(
         {:import, meta, [{:__aliases__, _aliases, module}, selector]},
         state
       ) do
    State.push_import(state, Import.new(module, selector, meta[:line]))
  end

  # wholesale import import MyModule
  defp analyze_node({:import, meta, [{:__aliases__, _aliases, module}]}, state) do
    State.push_import(state, Import.new(module, meta[:line]))
  end

  # clauses: ->
  defp analyze_node({clause, _, _} = quoted, state) when clause in @clauses do
    State.maybe_push_scope_for(state, quoted)
  end

  # blocks: do, else, etc.
  defp analyze_node({{:__block__, _, [block]}, _} = quoted, state)
       when block in @block_keywords do
    State.maybe_push_scope_for(state, quoted)
  end

  # catch-all
  defp analyze_node(_quoted, state) do
    state
  end

  defp maybe_push_implicit_alias(%State{} = state, [first_segment | _], line)
       when is_atom(first_segment) do
    segments =
      case State.current_module(state) do
        # the head element of top-level modules can be aliased, so we
        # must expand them
        [] ->
          expand_alias([first_segment], state)

        # if we have a current module, we prefix the first segment with it
        current_module ->
          current_module ++ [first_segment]
      end

    implicit_alias = Alias.new(segments, first_segment, line)
    State.push_alias(state, implicit_alias)
  end

  # don't create an implicit alias if the module is defined using complex forms:
  # defmodule __MODULE__.Foo do
  # defmodule unquote(...) do
  defp maybe_push_implicit_alias(%State{} = state, [non_atom | _], _line)
       when not is_atom(non_atom) do
    state
  end

  defp expand_alias({:__MODULE__, _, nil}, state) do
    State.current_module(state)
  end

  defp expand_alias({:__aliases__, _, segments}, state) do
    expand_alias(segments, state)
  end

  defp expand_alias([{:__MODULE__, _, nil} | segments], state) do
    State.current_module(state) ++ segments
  end

  defp expand_alias([first | rest], state) do
    alias_map = state |> State.current_scope() |> Scope.alias_map()

    case alias_map do
      %{^first => existing_alias} ->
        existing_alias.module ++ rest

      _ ->
        [first | rest]
    end
  end

  defp expand_alias(quoted, state) do
    reify_alias(State.current_module(state), List.wrap(quoted))
  end

  # Expands aliases given the rules in the special form
  # https://hexdocs.pm/elixir/1.13.4/Kernel.SpecialForms.html#__aliases__/1

  # When the head element is the atom :"Elixir", no expansion happens
  defp reify_alias(_, [:"Elixir" | _] = reified) do
    reified
  end

  # Without a current module, we can't expand a non-atom head element
  defp reify_alias([], [non_atom | rest]) when not is_atom(non_atom) do
    rest
  end

  # With no current module and an atom head, no expansion occurs
  defp reify_alias([], [atom | _] = reified) when is_atom(atom) do
    reified
  end

  # Expand current module
  defp reify_alias(current_module, [{:__MODULE__, _, nil} | rest]) do
    current_module ++ rest
  end

  # With a current module and an atom head, the alias is nested in the
  # current module
  defp reify_alias(current_module, [atom | _rest] = reified) when is_atom(atom) do
    current_module ++ reified
  end

  # In other cases, attempt to expand the unreified head element
  defp reify_alias(current_module, [unreified | rest]) do
    module = Module.concat(current_module)
    env = %Macro.Env{module: module}
    reified = Macro.expand(unreified, env)

    if is_atom(reified) do
      reified_segments = reified |> Module.split() |> Enum.map(&String.to_atom/1)
      reified_segments ++ rest
    else
      rest
    end
  end

  defp fetch_alias_as(options) do
    alias_as =
      Enum.find_value(options, fn
        {{:__block__, _, [:as]}, {:__aliases__, _, [alias_as]}} -> alias_as
        _ -> nil
      end)

    case alias_as do
      nil -> :error
      _ -> {:ok, alias_as}
    end
  end
end
