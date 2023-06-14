defmodule Lexical.RemoteControl.Completion do
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Completion.Candidate

  def elixir_sense_expand(doc_string, %Position{} = position) do
    # Add one to both the line and character, because elixir sense
    # has one-based lines, and the character needs to be after the context,
    # rather than in between.
    line = position.line
    character = position.character
    hint = ElixirSense.Core.Source.prefix(doc_string, line, character)

    if String.trim(hint) == "" do
      []
    else
      doc_string
      |> ElixirSense.suggestions(line, character)
      |> Enum.map(&Candidate.from_elixir_sense/1)
    end
  end
end
