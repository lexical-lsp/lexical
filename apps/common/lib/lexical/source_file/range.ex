defmodule Lexical.SourceFile.Range do
  @moduledoc """
  A range in a document
  """
  alias Lexical.SourceFile.Position

  defstruct start: nil, end: nil

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          end: non_neg_integer()
        }

  def new(%Position{} = start_pos, %Position{} = end_pos) do
    %__MODULE__{start: start_pos, end: end_pos}
  end
end

defimpl Lexical.Ranged.Native, for: Lexical.SourceFile.Range do
  alias Lexical.SourceFile.Range

  def from_lsp(%Range{} = range, _) do
    {:ok, range}
  end
end
