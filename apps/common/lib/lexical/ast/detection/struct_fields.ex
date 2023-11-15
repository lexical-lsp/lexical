defmodule Lexical.Ast.Detection.StructFields do
  alias Lexical.Ast
  alias Lexical.Ast.Detection
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    document
    |> Document.fragment(Position.new(document, position.line, 1), position)

    document
    |> Ast.cursor_path(position)
    |> Enum.any?(&match?({:%, _, _}, &1))
  end
end
