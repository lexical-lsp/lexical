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

  defstruct [
    :line,
    :character,
    valid?: false,
    context_line: nil,
    document_line_count: 0,
    starting_index: 1
  ]

  @type line :: non_neg_integer()
  @type character :: non_neg_integer()
  @type line_container :: Document.t() | Lines.t()

  @type t :: %__MODULE__{
          character: character(),
          context_line: Document.Line.t() | nil,
          document_line_count: non_neg_integer(),
          line: line(),
          starting_index: non_neg_integer(),
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
    line_count = Document.Lines.size(lines)
    starting_index = lines.starting_index

    case Lines.fetch_line(lines, line) do
      {:ok, context_line} ->
        %__MODULE__{
          character: character,
          context_line: context_line,
          document_line_count: line_count,
          line: line,
          starting_index: starting_index,
          valid?: true
        }

      :error ->
        %__MODULE__{
          line: line,
          character: character,
          document_line_count: line_count,
          starting_index: starting_index
        }
    end
  end
end

defimpl Inspect, for: Lexical.Document.Position do
  import Inspect.Algebra

  def inspect(nil, _), do: "nil"

  def inspect(pos, _) do
    concat(["LxPos", to_string(pos)])
  end
end

defimpl String.Chars, for: Lexical.Document.Position do
  def to_string(pos) do
    "<<#{pos.line}, #{pos.character}>>"
  end
end
