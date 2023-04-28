defmodule Lexical.Document.Range do
  @moduledoc """
  A range in a document
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
