defmodule Lexical.Ast.Detection.StructFieldValue do
  alias Lexical.Ast.Detection.StructFieldKey
  alias Lexical.Ast.Detection.StructFields
  alias Lexical.Document
  alias Lexical.Document.Position

  def detected?(%Document{} = document, %Position{} = position) do
    StructFields.detected?(document, position) and
      not StructFieldKey.detected?(document, position)
  end
end
