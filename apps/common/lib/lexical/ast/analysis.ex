defmodule Lexical.Ast.Analysis do
  @moduledoc """
  A data structure representing an analyzed AST.

  See `Lexical.Ast.analyze/1`.
  """

  alias Lexical.Ast.Analysis.Analyzer
  alias Lexical.Document

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
end
