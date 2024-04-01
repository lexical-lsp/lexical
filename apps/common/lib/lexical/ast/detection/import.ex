defmodule Lexical.Ast.Detection.Import do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Detection.Directive
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    Directive.detected?(analysis, position, 'import')
  end
end
