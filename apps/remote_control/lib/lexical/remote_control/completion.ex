defmodule Lexical.RemoteControl.Completion do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.SourceFile.Position

  def elixir_sense_expand(source, position) do
    # Add one to both the line and character, because elixir sense
    # has one-based lines, and the character needs to be after the context,
    # rather than in between.
    position = %Position{} = RemoteControl.namespace_struct(position)
    line = position.line + 1
    character = position.character + 1
    hint = ElixirSense.Core.Source.prefix(source, line, character)

    if String.trim(hint) == "" do
      []
    else
      source
      |> ElixirSense.suggestions(line, character)
      |> Enum.map(&Result.from_elixir_sense/1)
    end
  end
end
