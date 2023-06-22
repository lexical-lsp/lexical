defmodule Lexical.Document.Range do
  @moduledoc """
  A range in a document

  A range consists of a starting and ending position and includes all text in between.

  Note: To select an entire line, construct a range that runs from the first character on the line
  to the first character on the next line.

  ```
  whole_line = Range.new(
    Position.new(1, 1),
    Position.new(2, 1)
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

  def new(%Position{} = start_pos, %Position{} = end_pos) do
    %__MODULE__{start: start_pos, end: end_pos}
  end
end
