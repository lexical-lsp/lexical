defmodule Lexical.Ast.Analysis.Analyzer do
  @moduledoc false

  alias __MODULE__
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
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

  defmodule Scope do
    defstruct [:id, :range, module: [], parent_aliases: %{}, aliases: []]

    @type t :: %Scope{}

    def new(id, %Range{} = range, parent_aliases \\ %{}, module \\ []) do
      %Scope{id: id, range: range, module: module, parent_aliases: parent_aliases}
    end

    def global(%Range{} = range) do
      %Scope{id: :global, range: range}
    end

    @spec alias_map(Scope.t(), Position.t() | :end) :: %{module() => Scope.t()}
    def alias_map(%Scope{} = scope, position \\ :end) do
      end_line =
        case position do
          :end -> scope.range.end.line
          %Position{line: line} -> line
        end

      scope.aliases
      # sorting by line ensures that aliases on later lines
      # override aliases on earlier lines
      |> Enum.sort_by(& &1.line)
      |> Enum.take_while(&(&1.line <= end_line))
      |> Map.new(&{&1.as, &1})
      |> Enum.into(scope.parent_aliases)
    end

    def empty?(%Scope{aliases: []}), do: true
    def empty?(%Scope{}), do: false
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
      parent_aliases = state |> current_scope() |> Scope.alias_map()
      scope = Scope.new(id, range, parent_aliases, module)
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
          {quoted, pre(quoted, state)}
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
  defp pre({:defmodule, meta, [{:__aliases__, _, segments} | _]} = quoted, state) do
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
  defp pre({:alias, meta, [{{:., _, [aliases, :{}]}, _, aliases_nodes}]}, state) do
    base_segments = expand_alias(aliases, state)

    Enum.reduce(aliases_nodes, state, fn {:__aliases__, _, segments}, state ->
      alias = Alias.new(base_segments ++ segments, List.last(segments), meta[:line])
      State.push_alias(state, alias)
    end)
  end

  # alias Foo
  # alias Foo.Bar
  # alias __MODULE__.Foo
  defp pre({:alias, meta, [aliases]}, state) do
    case expand_alias(aliases, state) do
      [_ | _] = segments ->
        alias = Alias.new(segments, List.last(segments), meta[:line])
        State.push_alias(state, alias)

      [] ->
        state
    end
  end

  # alias Foo, as: Bar
  defp pre({:alias, meta, [aliases, options]}, state) do
    with {:ok, alias_as} <- fetch_alias_as(options),
         [_ | _] = segments <- expand_alias(aliases, state) do
      alias = Alias.new(segments, alias_as, meta[:line])
      State.push_alias(state, alias)
    else
      _ ->
        pre({:alias, meta, [aliases]}, state)
    end
  end

  # clauses: ->
  defp pre({clause, _, _} = quoted, state) when clause in @clauses do
    State.maybe_push_scope_for(state, quoted)
  end

  # blocks: do, else, etc.
  defp pre({{:__block__, _, [block]}, _} = quoted, state) when block in @block_keywords do
    State.maybe_push_scope_for(state, quoted)
  end

  # catch-all
  defp pre(_quoted, state) do
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

    implicit_alias = %Alias{
      as: first_segment,
      module: segments,
      line: line
    }

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
    env = %Macro.Env{module: current_module}
    reified = Macro.expand(unreified, env)

    if is_atom(reified) do
      [reified | rest]
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
