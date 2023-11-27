defmodule Lexical.Ast.Detection.Type do
  alias Lexical.Ast.Detection
  alias Lexical.Document
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    ancestor_is_type?(document, position)
  end
end
