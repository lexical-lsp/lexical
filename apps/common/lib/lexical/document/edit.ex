defmodule Lexical.Document.Edit do
  alias Lexical.Document.Range
  alias Lexical.StructAccess

  defstruct [:text, :range]

  @type t :: %__MODULE__{
          text: String.t(),
          range: Range.t() | nil
        }

  use StructAccess

  @spec new(String.t(), Range.t() | nil) :: t
  @spec new(String.t()) :: t
  def new(text) when is_binary(text) do
    %__MODULE__{text: text}
  end

  def new(text, %Range{} = range) do
    %__MODULE__{text: text, range: range}
  end

  def new(text, nil) when is_binary(text) do
    %__MODULE__{text: text}
  end
end
