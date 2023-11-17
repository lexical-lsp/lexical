defmodule Lexical.Ast.Detection.Spec do
  alias Lexical.Ast.Detection
  alias Lexical.Document
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    ancestor_is_spec?(document, position)
  end
end
