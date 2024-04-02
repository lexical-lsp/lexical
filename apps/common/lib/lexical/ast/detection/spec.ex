defmodule Lexical.Ast.Detection.Spec do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    ancestor_is_spec?(analysis, position)
  end
end
