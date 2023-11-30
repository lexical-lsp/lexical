defmodule Lexical.Ast.Analysis do
  @moduledoc """
  A data structure representing an analyzed AST.

  See `Lexical.Ast.analyze/1`.
  """

  alias Lexical.Ast.Analysis.Analyzer
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  defstruct [:ast, :document, :parse_error, scopes: [], valid?: true]

  @type t :: %__MODULE__{}

  @doc false
  def new(parse_result, document)

  def new({:ok, ast}, %Document{} = document) do
    scopes = Analyzer.traverse(ast, document)

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
  def aliases_at(%__MODULE__{} = analysis, %Position{} = position) do
    case scopes_at(analysis, position) do
      [%Analyzer.Scope{} = scope | _] ->
        scope
        |> Analyzer.Scope.alias_map(position)
        |> Map.new(fn {as, %Analyzer.Alias{} = alias} ->
          {as, Analyzer.Alias.to_module(alias)}
        end)

      [] ->
        %{}
    end
  end

  def resolve_local_call(%__MODULE__{} = analysis, %Position{} = position, function_name, arity) do
    maybe_imported_mfa =
      analysis
      |> imports_at(position)
      |> Enum.find(fn
        {_, ^function_name, ^arity} -> true
        _ -> false
      end)

    if is_nil(maybe_imported_mfa) do
      aliases = aliases_at(analysis, position)
      current_module = aliases[:__MODULE__]
      {current_module, function_name, arity}
    else
      maybe_imported_mfa
    end
  end

  def imports_at(%__MODULE__{} = analysis, %Position{} = position) do
    case scopes_at(analysis, position) do
      [%Analyzer.Scope{} = scope | _] ->
        Analyzer.Scope.imports(scope, position)

      _ ->
        MapSet.new()
    end
  end

  defp scopes_at(%__MODULE__{scopes: scopes}, %Position{} = position) do
    scopes
    |> Enum.filter(fn %Analyzer.Scope{range: range} = scope ->
      scope.id == :global or Range.contains?(range, position)
    end)
    |> Enum.sort_by(
      fn
        %Analyzer.Scope{id: :global} -> 0
        %Analyzer.Scope{range: range} -> {range.start.line, range.start.character}
      end,
      :desc
    )
  end
end
