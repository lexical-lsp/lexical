defmodule Lexical.Ast.Detection.StructFields do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    analysis.document
    |> Ast.cursor_path(position)
    |> Enum.any?(&match?({:%, _, _}, &1))
  end
end
