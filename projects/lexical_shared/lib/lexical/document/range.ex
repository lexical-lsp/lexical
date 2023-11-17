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
  def contains?(%__MODULE__{} = range, %Position{} = position) do
    %__MODULE__{start: start_pos, end: end_pos} = range

    cond do
      position.line == start_pos.line ->
        position.character >= start_pos.character

      position.line == end_pos.line ->
        position.character < end_pos.character

      true ->
        position.line > start_pos.line and position.line < end_pos.line
    end
  end
end
