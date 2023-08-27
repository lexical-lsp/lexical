defmodule Lexical.Ast.Aliases do
  defmodule Alias do
    defstruct [:from, :to]

    def new(from, to) do
      %__MODULE__{from: from, to: to}
    end
  end

  defmodule Scope do
    defstruct [:end_position, :current_module, :aliases, :on_exit]

    def new(end_position, current_module, on_exit \\ &Function.identity/1) do
      %__MODULE__{
        aliases: %{},
        current_module: current_module,
        end_position: end_position,
        on_exit: on_exit
      }
    end

    def global do
      new({:infinity, :infinity}, nil)
    end

    def ended?(%__MODULE__{end_position: {:infinity, :infinity}}, _) do
      false
    end

    def ended?(%__MODULE__{} = scope, {line, column}) do
      {end_line, end_column} = scope.end_position

      if line == end_line do
        column >= end_column
      else
        line > end_line
      end
    end

    def put_alias(%__MODULE__{} = scope, _, :skip) do
      scope
    end

    def put_alias(%__MODULE__{} = scope, from, to) do
      [first | rest] = from

      # This allows a pre-existing alias to define another alias like
      # alias Foo.Bar.Baz
      # alias Baz.Quux
      from =
        case scope.aliases do
          %{^first => to_alias} -> Module.split(to_alias.from) ++ rest
          _ -> from
        end

      new_alias = Alias.new(ensure_alias(scope, from), ensure_alias(scope, to))
      %__MODULE__{scope | aliases: Map.put(scope.aliases, new_alias.to, new_alias)}
    end

    defp ensure_alias(%__MODULE__{} = scope, [:__MODULE__ | rest]) do
      Module.concat([scope.current_module | rest])
    end

    defp ensure_alias(%__MODULE__{}, alias_list) when is_list(alias_list) do
      Module.concat(alias_list)
    end

    defp ensure_alias(%__MODULE__{}, alias_atom) when is_atom(alias_atom) do
      alias_atom
    end
  end

  defmodule Reducer do
    defstruct scopes: []

    def new do
      %__MODULE__{scopes: [Scope.global()]}
    end

    def update(%__MODULE__{} = reducer, elem) do
      reducer
      |> maybe_pop_scope(elem)
      |> apply_ast(elem)
    end

    def current_module(%__MODULE__{} = reducer) do
      current_scope(reducer).current_module
    end

    def aliases(%__MODULE__{} = reducer) do
      reducer.scopes
      |> Enum.reverse()
      |> Enum.flat_map(&Map.to_list(&1.aliases))
      |> Map.new(fn {k, %Alias{} = scope_alias} -> {k, scope_alias.from} end)
      |> Map.put(:__MODULE__, current_module(reducer))
    end

    # defmodule MyModule do
    defp apply_ast(
           %__MODULE__{} = reducer,
           {:defmodule, metadata, [{:__aliases__, _, module_name}, _block]}
         ) do
      module_alias =
        case current_module(reducer) do
          nil ->
            module_name

          current_module ->
            Module.split(current_module) ++ module_name
        end

      current_module_alias =
        case module_name do
          [current] -> current
          _ -> :skip
        end

      reducer
      |> push_scope(metadata, module_alias, &put_alias(&1, module_alias, current_module_alias))
      |> put_alias(module_alias, current_module_alias)
    end

    # A simple alias: alias Foo.Bar
    defp apply_ast(%__MODULE__{} = reducer, {:alias, _metadata, [{:__aliases__, _, from}]}) do
      to = List.last(from)
      put_alias(reducer, normalize_from(from), to)
    end

    # An alias with a specified name: alias Foo.Bar, as: FooBar
    defp apply_ast(
           %__MODULE__{} = reducer,
           {:alias, _metadata,
            [{:__aliases__, _, from}, [{{:__block__, _, [:as]}, {:__aliases__, _, [to]}}]]}
         ) do
      put_alias(reducer, normalize_from(from), to)
    end

    # A multiple alias: alias Foo.Bar.{First, Second, Third.Fourth}
    defp apply_ast(
           %__MODULE__{} = reducer,
           {:alias, _, [{{:., _, [{:__aliases__, _, from_alias}, :{}]}, _, destinations}]}
         ) do
      from_alias = normalize_from(from_alias)
      apply_multiple_aliases(reducer, from_alias, destinations)
    end

    # An alias for __MODULE__: alias __MODULE__

    defp apply_ast(%__MODULE__{} = reducer, {:alias, _, [{:__MODULE__, _, _}]}) do
      from_alias = reducer |> current_module() |> Module.split() |> Enum.map(&String.to_atom/1)
      to = List.last(from_alias)
      put_alias(reducer, from_alias, to)
    end

    # A muliple alias starting with __MODULE__: alias __MODULE__.{First, Second}
    defp apply_ast(
           %__MODULE__{} = reducer,
           {:alias, _, [{{:., _, [{:__MODULE__, _, _}, :{}]}, _, destinations}]}
         ) do
      from_alias = [:__MODULE__]
      apply_multiple_aliases(reducer, from_alias, destinations)
    end

    # This clause will match anything that has a do block, and will push a new scope.
    # This will match functions and any block-like macro DSLs people implement
    defp apply_ast(%__MODULE__{} = reducer, {_definition, metadata, _body}) do
      if Keyword.has_key?(metadata, :end) do
        push_scope(reducer, metadata, current_module(reducer))
      else
        reducer
      end
    end

    defp apply_ast(%__MODULE__{} = reducer, _elem) do
      reducer
    end

    defp apply_multiple_aliases(%__MODULE__{} = reducer, from_alias, destinations) do
      Enum.reduce(destinations, reducer, fn
        {:__aliases__, _, to_alias}, reducer ->
          from =
            case from_alias do
              [:__MODULE__ | rest] ->
                [:__MODULE__ | rest ++ to_alias]

              from ->
                from ++ to_alias
            end

          to = List.last(from)
          put_alias(reducer, from, to)

        {:__cursor__, _, _}, reducer ->
          reducer
      end)
    end

    defp put_alias(%__MODULE__{} = reducer, _, :skip) do
      reducer
    end

    defp put_alias(%__MODULE__{} = reducer, from, to) do
      scope =
        reducer
        |> current_scope()
        |> Scope.put_alias(from, to)

      replace_current_scope(reducer, scope)
    end

    defp current_scope(%__MODULE__{scopes: [current | _]}) do
      current
    end

    defp replace_current_scope(%__MODULE__{scopes: [_ | rest]} = reducer, scope) do
      %__MODULE__{reducer | scopes: [scope | rest]}
    end

    defp ensure_alias(%__MODULE__{} = reducer, [{:__MODULE__, _, _}, rest]) do
      reducer
      |> current_module()
      |> Module.concat(rest)
    end

    defp ensure_alias(%__MODULE__{}, alias_list) when is_list(alias_list) do
      Module.concat(alias_list)
    end

    defp ensure_alias(%__MODULE__{}, alias_atom) when is_atom(alias_atom) do
      alias_atom
    end

    defp push_scope(
           %__MODULE__{} = reducer,
           metadata,
           current_module,
           on_exit \\ &Function.identity/1
         ) do
      end_position = {get_in(metadata, [:end, :line]), get_in(metadata, [:end, :column])}
      current_module = ensure_alias(reducer, current_module)
      new_scopes = [Scope.new(end_position, current_module, on_exit) | reducer.scopes]

      %__MODULE__{reducer | scopes: new_scopes}
    end

    defp maybe_pop_scope(%__MODULE__{} = reducer, {_, metadata, _}) do
      with {:ok, current_line} <- Keyword.fetch(metadata, :line),
           {:ok, current_column} <- Keyword.fetch(metadata, :column),
           [current_scope | scopes] <- reducer.scopes,
           true <- Scope.ended?(current_scope, {current_line, current_column}) do
        current_scope.on_exit.(%__MODULE__{reducer | scopes: scopes})
      else
        _ ->
          reducer
      end
    end

    defp maybe_pop_scope(%__MODULE__{} = reducer, _) do
      reducer
    end

    defp normalize_from([{:__MODULE__, _, _} | rest]) do
      [:__MODULE__ | rest]
    end

    defp normalize_from(from) do
      from
    end
  end

  @moduledoc """
  Support for resolving module aliases.
  """

  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position

  @doc """
  Returns the aliases available in the document at a given position.

  May return aliases even in the event of syntax errors.
  """
  @spec at(Document.t(), Position.t() | {Position.line(), Position.character()}) ::
          {:ok, %{Ast.short_alias() => module()}} | {:error, Ast.parse_error()}
  def at(%Document{} = doc, {line, character}) do
    at(doc, Position.new(line, character))
  end

  def at(%Document{} = document, %Position{} = position) do
    with {:ok, quoted} <- Ast.fragment(document, position) do
      reducer = Reducer.new()

      {_ast, reducer} = Macro.prewalk(quoted, reducer, &collect/2)

      aliases = Reducer.aliases(reducer)
      {:ok, aliases}
    end
  end

  @doc """
  Returns the aliases available in the document at the given position.

  This function works like `at/2`, but takes Elixir AST as its first argument, rather than a Document.
  This allows you to parse a document once and make repeated queries against it for vastly improved performance.
  """
  def at_ast(ast, {line, character}) do
    at_ast(ast, Position.new(line, character))
  end

  def at_ast(ast, %Position{} = position) do
    aliases =
      ast
      |> Ast.traverse_until(Reducer.new(), &collect/2, position)
      |> Reducer.aliases()

    {:ok, aliases}
  end

  defp collect(elem, %Reducer{} = reducer) do
    Reducer.update(reducer, elem)
  end
end
