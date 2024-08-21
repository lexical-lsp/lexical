defmodule Lexical.Ast.Detection.Import do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Detection.Directive
  alias Lexical.Document.Position

  use Detection

  @doc """
  Recognizes an import at the current position.
  """
  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    Directive.detected?(analysis, position, ~c"import")
  end
end
