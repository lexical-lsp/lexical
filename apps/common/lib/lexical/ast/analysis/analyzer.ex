defmodule Lexical.Ast.Analysis.Analyzer do
  @moduledoc false

  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Sourceror.Zipper

  @id :_id

  @block_keywords [:do, :else, :rescue, :catch, :after]
  @clauses [:->]

  defmodule State do
    alias Lexical.Ast.Analysis.Analyzer

    defstruct [:document, scopes: [], visited: %{}]

    def new(%Document{} = document, %Range{} = root_range) do
      root_scope = Scope.root(root_range)
      %State{document: document, scopes: [root_scope]}
    end

    def current_scope(%State{scopes: [scope | _]}), do: scope

    def current_module(%State{} = state) do
      current_scope(state).module
    end

    def push_scope(%State{} = state, %Scope{} = scope) do
      Map.update!(state, :scopes, &[scope | &1])
    end

    def push_scope(%State{} = state, id, %Range{} = range, kind, module) when is_list(module) do
      parent_aliases = state |> current_scope() |> Scope.alias_map()
      scope = Scope.new(id, range, kind, module, parent_aliases)
      push_scope(state, scope)
    end

    def push_scope_for(%State{} = state, quoted, %Range{} = range, kind, module) do
      module = module || current_module(state)
      id = Analyzer.node_id(quoted)
      push_scope(state, id, range, kind, module)
    end

    def push_scope_for(%State{} = state, quoted, kind, module) do
      range = Ast.get_range(quoted, state.document)
      push_scope_for(state, quoted, range, kind, module)
    end

    def maybe_push_scope_for(%State{} = state, quoted, kind) do
      case Ast.get_range(quoted, state.document) do
        %Range{} = range ->
          push_scope_for(state, quoted, range, kind, nil)

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

    defp update_current_scope(%State{} = state, fun) do
      update_in(state, [Access.key(:scopes), Access.at!(0)], fn %Scope{} = scope ->
        fun.(scope)
      end)
    end
  end

  @doc """
  Traverses an AST, returning a list of scopes in their order of appearance.
  """
  @spec extract_scopes(Macro.t(), Document.t()) :: {Analysis.analyzed_ast(), [Scope.t()]}
  def extract_scopes(quoted, %Document{} = document) do
    quoted = preprocess(quoted)
    root_range = root_range(quoted, document)

    {quoted, state} =
      Macro.traverse(
        quoted,
        State.new(document, root_range),
        fn quoted, state ->
          {quoted, analyze_node(quoted, state)}
        end,
        fn quoted, state ->
          case {node_id(quoted), State.current_scope(state)} do
            {id, %Scope{id: id}} ->
              {quoted, State.pop_scope(state)}

            _ ->
              {quoted, state}
          end
        end
      )

    unless length(state.scopes) == 1 do
      raise RuntimeError,
            "invariant not met, :scopes should only contain the root scope: #{inspect(state)}"
    end

    scopes =
      state
      # pop the final, root scope
      |> State.pop_scope()
      |> Map.fetch!(:visited)
      |> correct_ranges(quoted, document)
      |> Map.values()
      |> sort_scopes()

    {quoted, scopes}
  end

  defp preprocess(quoted) do
    Macro.prewalk(quoted, &with_node_id/1)
  end

  defp correct_ranges(scopes, quoted, document) do
    {_zipper, scopes} =
      quoted
      |> Zipper.zip()
      |> Zipper.traverse(scopes, fn %Zipper{node: node} = zipper, scopes ->
        id = node_id(node)

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
        case zipper |> Zipper.up() |> Zipper.up() |> Zipper.node() |> Sourceror.get_range() do
          %{end: parent_end} ->
            new_end = Position.new(document, parent_end[:line], parent_end[:column])
            put_in(scope.range.end, new_end)

          _ ->
            scope
        end
    end
  end

  defp maybe_correct_range(scope, _zipper, _document) do
    scope
  end

  defp sort_scopes(scopes) do
    Enum.sort_by(
      scopes,
      fn
        %Scope{id: :root} -> 0
        %Scope{range: range} -> {range.start.line, range.start.character}
      end,
      :asc
    )
  end

  # add a unique ID to 3-element tuples
  defp with_node_id({_, _, _} = quoted) do
    Macro.update_meta(quoted, &Keyword.put(&1, @id, make_ref()))
  end

  defp with_node_id(quoted) do
    quoted
  end

  @doc false
  def node_id({_, meta, _}) when is_list(meta) do
    Keyword.get(meta, @id)
  end

  def node_id({left, right}) do
    {node_id(left), node_id(right)}
  end

  def node_id(list) when is_list(list) do
    Enum.map(list, &node_id/1)
  end

  def node_id(_) do
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
    |> State.push_scope_for(quoted, :module, module)
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

  # clauses: ->
  defp analyze_node({clause, _, _} = quoted, state) when clause in @clauses do
    State.maybe_push_scope_for(state, quoted, :block)
  end

  # blocks: do, else, etc.
  defp analyze_node({{:__block__, _, [block]}, _} = quoted, state)
       when block in @block_keywords do
    State.maybe_push_scope_for(state, quoted, :block)
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

  defp root_range(quoted, %Document{} = document) do
    end_line =
      case Sourceror.get_range(quoted) do
        %{end: end_pos} -> end_pos[:line]
        _ -> 0
      end

    lines_in_doc = Document.size(document)

    Range.new(
      Position.new(document, 1, 1),
      Position.new(document, max(end_line, lines_in_doc) + 1, 1)
    )
  end
end
