defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Lexical.Document
  alias Lexical.Document.Position

  def definition(%Document{} = source_file, %Position{} = position) do
    source_file
    |> Document.to_string()
    |> ElixirSense.definition(position.line, position.character)
  end
end
