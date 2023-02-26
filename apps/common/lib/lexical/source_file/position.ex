defmodule Lexical.SourceFile.Position do
  defstruct [:line, :character]

  @type t :: %__MODULE__{
          line: non_neg_integer(),
          character: non_neg_integer()
        }

  def new(line, character) when is_number(line) and is_number(character) do
    %__MODULE__{line: line, character: character}
  end

  defimpl Lexical.Ranged.Native, for: Lexical.SourceFile.Position do
    alias Lexical.SourceFile.Position

    def from_lsp(%Position{} = position, _) do
      {:ok, position}
    end
  end
end
