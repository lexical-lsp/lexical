defmodule Lexical.Ast.Analysis do
  @moduledoc """
  A data structure representing an analyzed AST.

  See `Lexical.Ast.analyze/1`.
  """

  alias Lexical.Ast
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Ast.Analysis.Analyzer
  alias Lexical.Ast.Analysis.Scope
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  defstruct [:ast, :document, :parse_error, :tree, valid?: true]

  @type t :: %__MODULE__{
          ast: analyzed_ast | nil,
          document: Document.t(),
          parse_error: Ast.parse_error() | nil,
          tree: scope_tree,
          valid?: boolean()
        }

  @typedoc "A `t:Macro.t/0` that has undergone analysis"
  @type analyzed_ast :: Macro.t()

  @typedoc "A basic tree structure representing nested scopes"
  @type scope_tree :: %{scope: Scope.t(), children: [scope_tree]}

  @typedoc "An atom that might be used as an alias. For example: `:Foo`"
  @type module_alias :: atom()

  @typedoc "A list of atoms representing the segments of a module. For example: `[:Foo, :Bar]`"
  @type module_segments :: [atom()]

  @type alias_map :: %{module_alias => module_segments}

  @doc false
  def new(parse_result, document)

  def new({:ok, ast}, %Document{} = document) do
    scopes = Analyzer.extract_scopes(ast, document)

    %__MODULE__{
      ast: ast,
      document: document,
      tree: scopes_to_tree(scopes)
    }
  end

  def new(error, document) do
    %__MODULE__{
      document: document,
      parse_error: error,
      valid?: false
    }
  end

  @doc """
  Retrieve the id of a node in an analyzed AST.
  """
  @spec scope_id(analyzed_ast) :: Scope.id() | nil
  defdelegate scope_id(quoted), to: Analyzer

  @doc """
  Retrieve the id of the nearest scope for the quoted form of the given kind.
  """
  @spec scope_id_at(analyzed_ast, Scope.kind(), t) :: Scope.id() | nil
  def scope_id_at(quoted, kind, %__MODULE__{} = analysis) do
    with %Position{} = position <- Ast.get_position(quoted, analysis) do
      analysis
      |> scopes_at(position)
      |> Enum.find_value(fn
        %Scope{kind: ^kind, id: id} -> id
        _ -> nil
      end)
    end
  end

  @doc false
  @spec aliases_at(t, Position.t()) :: alias_map
  def aliases_at(%__MODULE__{} = analysis, %Position{} = position) do
    case scopes_at(analysis, position) do
      [%Scope{} = scope | _] ->
        scope
        |> Scope.alias_map(position)
        |> Map.new(fn {as, %Alias{} = alias} ->
          {as, Alias.to_module(alias)}
        end)

      [] ->
        %{}
    end
  end

  defp scopes_at(%__MODULE__{tree: tree}, %Position{} = position) do
    tree |> scopes_at(position) |> Enum.reverse()
  end

  defp scopes_at(%{scope: scope, children: children}, %Position{} = position) do
    if Range.contains?(scope.range, position) do
      child_scopes =
        Enum.find_value(children, [], fn child ->
          case scopes_at(child, position) do
            [] -> nil
            scopes -> scopes
          end
        end)

      [scope | child_scopes]
    else
      []
    end
  end

  defp scopes_to_tree([root | rest]) do
    {root_tree, []} = scope_to_tree(%{scope: root, children: []}, rest)
    root_tree
  end

  defp scope_to_tree(%{scope: parent, children: children}, [maybe_child | rest]) do
    if Range.contains?(parent.range, maybe_child.range, true) do
      {child_tree, rest} = scope_to_tree(%{scope: maybe_child, children: []}, rest)
      scope_to_tree(%{scope: parent, children: [child_tree | children]}, rest)
    else
      {%{scope: parent, children: Enum.reverse(children)}, [maybe_child | rest]}
    end
  end

  defp scope_to_tree(%{scope: scope, children: children}, []) do
    {%{scope: scope, children: Enum.reverse(children)}, []}
  end
end
