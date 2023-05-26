defmodule Lexical.Document.Position do
  defstruct [:line, :character]

  @type t :: %__MODULE__{
          line: non_neg_integer(),
          character: non_neg_integer()
        }

  use Lexical.StructAccess

  def new(line, character) when is_number(line) and is_number(character) do
    %__MODULE__{line: line, character: character}
  end
end
