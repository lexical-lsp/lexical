defmodule Lexical.Document.Position do
  @moduledoc """
  A position inside of a document

  This struct represents a cursor position inside a document, using one-based line and character
  numbers. It's important to note that the position starts before the character given, so positions
  are inclusive of the given character.

  Given the following line of text:
  "Hello there, welcome to lexical"

  the position: `%Lexical.Document.Position{line: 1, character: 1}` starts before the "H" in "Hello"
  """

  alias Lexical.Document
  alias Lexical.Document.Lines

  defstruct [:line, :character, valid?: false, context_line: nil]

  @type line :: non_neg_integer()
  @type character :: non_neg_integer()
  @type line_container :: Document.t() | Lines.t()

  @type t :: %__MODULE__{
          line: line(),
          character: character(),
          context_line: Document.Line.t(),
          valid?: boolean()
        }

  use Lexical.StructAccess

  @spec new(line_container(), line(), character()) :: t
  def new(%Document{} = document, line, character)
      when is_number(line) and is_number(character) do
    new(document.lines, line, character)
  end

  def new(%Document.Lines{} = lines, line, character)
      when is_number(line) and is_number(character) do
    case Lines.fetch_line(lines, line) do
      {:ok, context_line} ->
        %__MODULE__{line: line, character: character, context_line: context_line, valid?: true}

      :error ->
        %__MODULE__{line: line, character: character}
    end
  end
end
