defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Lexical.Document
  alias Lexical.Document.Position

  def definition(%Document{} = document, %Position{} = position) do
    document
    |> Document.to_string()
    |> ElixirSense.definition(position.line, position.character)
  end
end
