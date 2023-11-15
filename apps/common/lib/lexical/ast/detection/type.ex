defmodule Lexical.Ast.Detection.Type do
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Detection.Ancestor
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    Ancestor.is_type?(document, position)
  end
end
