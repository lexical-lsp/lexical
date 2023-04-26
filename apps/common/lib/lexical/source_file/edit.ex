defmodule Lexical.SourceFile.Edit do
  defstruct [:text, :range]

  @type t :: %__MODULE__{
          text: String.t(),
          range: Lexical.SourceFile.Range.t() | nil
        }

  @spec new(String.t(), Range.t()) :: t
  @spec new(String.t()) :: t

  use Lexical.StructAccess

  def new(text, range \\ nil) do
    %__MODULE__{text: text, range: range}
  end
end
