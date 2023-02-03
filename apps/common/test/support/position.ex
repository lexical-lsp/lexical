# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Position do
  defstruct [:character, :line]

  def new(opts \\ []) do
    %__MODULE__{
      character: Keyword.get(opts, :character, 0),
      line: Keyword.get(opts, :line, 0)
    }
  end
end
