defmodule Lexical.Ast.Analysis.Analyzer.State do
  alias Lexical.Ast.Analysis.Analyzer
  alias Lexical.Ast.Analysis.Analyzer.Alias
  alias Lexical.Ast.Analysis.Analyzer.Import
  alias Lexical.Ast.Analysis.Analyzer.Scope
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  defstruct [:document, scopes: [], visited: %{}]

  def new(%Document{} = document) do
    state = %__MODULE__{document: document}

    scope =
      document
      |> global_range()
      |> Scope.global()

    push_scope(state, scope)
  end

  def current_scope(%__MODULE__{scopes: [scope | _]}), do: scope

  def current_module(%__MODULE__{} = state) do
    current_scope(state).module
  end

  def push_scope(%__MODULE__{} = state, %Scope{} = scope) do
    Map.update!(state, :scopes, &[scope | &1])
  end

  def push_scope(%__MODULE__{} = state, id, %Range{} = range, module) when is_list(module) do
    scope =
      state
      |> current_scope()
      |> Scope.new(id, range, module)

    push_scope(state, scope)
  end

  def push_scope_for(%__MODULE__{} = state, quoted, %Range{} = range, module) do
    module = module || current_module(state)

    id = Analyzer.scope_id(quoted)
    push_scope(state, id, range, module)
  end

  def push_scope_for(%__MODULE__{} = state, quoted, module) do
    range = get_range(quoted, state.document)
    push_scope_for(state, quoted, range, module)
  end

  def maybe_push_scope_for(%__MODULE__{} = state, quoted) do
    case get_range(quoted, state.document) do
      %Range{} = range ->
        push_scope_for(state, quoted, range, nil)

      nil ->
        state
    end
  end

  def pop_scope(%__MODULE__{scopes: [scope | rest]} = state) do
    %__MODULE__{state | scopes: rest, visited: Map.put(state.visited, scope.id, scope)}
  end

  def push_alias(%__MODULE__{} = state, %Alias{} = alias) do
    update_current_scope(state, fn %Scope{} = scope ->
      [prefix | rest] = alias.module

      alias =
        case Scope.fetch_alias_with_prefix(scope, prefix) do
          {:ok, %Alias{} = existing_alias} ->
            %Alias{alias | module: existing_alias.module ++ rest}

          :error ->
            alias
        end

      Map.update!(scope, :aliases, &[alias | &1])
    end)
  end

  def push_import(%__MODULE__{} = state, %Import{} = import) do
    update_current_scope(state, fn %Scope{} = scope ->
      Map.update!(scope, :imports, &[import | &1])
    end)
  end

  defp update_current_scope(%__MODULE__{} = state, fun) do
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
