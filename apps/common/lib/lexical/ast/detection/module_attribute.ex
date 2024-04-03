defmodule Lexical.Ast.Detection.ModuleAttribute do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    ancestor_is_attribute?(analysis, position)
  end

  def detected?(%Analysis{} = analysis, %Position{} = position, name) do
    ancestor_is_attribute?(analysis, position, name)
  end
end
