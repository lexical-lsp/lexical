defmodule Lexical.Ast.Detection.Type do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    ancestor_is_type?(analysis, position)
  end
end
