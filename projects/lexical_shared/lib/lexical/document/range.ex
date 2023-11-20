defmodule Lexical.Document.Range do
  @moduledoc """
  A range in a document

  Note that ranges represent a cursor position, and so are inclusive of
  lines, but exclusive of the end position.

  Note: To select an entire line, construct a range that runs from the
  first character on the line to the first character on the next line.

  ```
  whole_line =
    Range.new(
      Position.new(doc, 1, 1),
      Position.new(doc, 2, 1)
    )
  ```
  """
  alias Lexical.Document.Position

  defstruct start: nil, end: nil

  @type t :: %__MODULE__{
          start: Position.t(),
          end: Position.t()
        }

  use Lexical.StructAccess

  @doc """
  Builds a new range.
  """
  def new(%Position{} = start_pos, %Position{} = end_pos) do
    %__MODULE__{start: start_pos, end: end_pos}
  end

  @doc """
  Returns whether the range contains the given position.
  """
  def contains?(range, range_or_position, inclusive_end_character? \\ false)

  def contains?(%__MODULE__{} = range, %Position{} = position, inclusive?) do
    %__MODULE__{start: start_pos, end: end_pos} = range

    cond do
      position.line == start_pos.line ->
        position.character >= start_pos.character

      position.line == end_pos.line ->
        if inclusive? do
          position.character <= end_pos.character
        else
          position.character < end_pos.character
        end

      true ->
        position.line > start_pos.line and position.line < end_pos.line
    end
  end

  def contains?(%__MODULE__{} = range, %__MODULE__{} = maybe_child, inclusive?) do
    contains?(range, maybe_child.start, inclusive?) and
      contains?(range, maybe_child.end, inclusive?)
  end
end
