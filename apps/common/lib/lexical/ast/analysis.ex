defmodule Lexical.Ast.Analysis do
  @moduledoc """
  A data structure representing an analyzed AST.

  See `Lexical.Ast.analyze/1`.
  """

  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Import
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Ast.Analysis.State
  alias Lexical.Document
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Sourceror.Zipper

  defstruct [:ast, :document, :parse_error, scopes: [], valid?: true]

  @type t :: %__MODULE__{}
  @scope_id :_scope_id

  @block_keywords [:do, :else, :rescue, :catch, :after]
  @clauses [:->]

  @doc false
  def new(parse_result, document)

  def new({:ok, ast}, %Document{} = document) do
    scopes = traverse(ast, document)

    %__MODULE__{
      ast: ast,
      document: document,
      scopes: scopes
    }
  end

  def new(error, document) do
    %__MODULE__{
      document: document,
      parse_error: error,
      valid?: false
    }
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

  defp traverse(quoted, %Document{} = document) do
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

        case Sourceror.get_range(parent) do
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

  # add a unique ID to 3-element tuples
  defp with_scope_id({_, _, _} = quoted) do
    Macro.update_meta(quoted, &Keyword.put(&1, @scope_id, make_ref()))
  end

  defp with_scope_id(quoted) do
    quoted
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
