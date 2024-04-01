defmodule Lexical.Ast.Detection.Comment do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position

  def detected?(%Analysis{} = analysis, %Position{} = position) do
    Analysis.commented?(analysis, position)
  end
end
