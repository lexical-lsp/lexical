defmodule Lexical.SourceFile.Edit do
  defstruct [:text, :range]

  @type t :: %__MODULE__{
          text: String.t(),
          range: Lexical.SourceFile.Range.t() | nil
        }

  @spec new(String.t(), Lexical.SourceFile.Range.t() | nil) :: t
  @spec new(String.t()) :: t

  alias Lexical.SourceFile.Range
  use Lexical.StructAccess

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
