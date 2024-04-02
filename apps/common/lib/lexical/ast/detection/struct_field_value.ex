defmodule Lexical.Ast.Detection.StructFieldValue do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection.StructFieldKey
  alias Lexical.Ast.Detection.StructFields
  alias Lexical.Document.Position

  def detected?(%Analysis{} = analysis, %Position{} = position) do
    StructFields.detected?(analysis, position) and
      not StructFieldKey.detected?(analysis, position)
  end
end
