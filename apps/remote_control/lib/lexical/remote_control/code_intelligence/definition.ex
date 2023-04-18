defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  def definition(%SourceFile{} = source_file, %Position{} = position) do
    source_file
    |> SourceFile.to_string()
    |> ElixirSense.definition(position.line, position.character)
  end
end
