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

  defstruct [:line, :character]

  @type line :: non_neg_integer()
  @type character :: non_neg_integer()

  @type t :: %__MODULE__{
          line: line(),
          character: character()
        }

  use Lexical.StructAccess

  @spec new(line(), character()) :: t
  def new(line, character) when is_number(line) and is_number(character) do
    %__MODULE__{line: line, character: character}
  end
end
