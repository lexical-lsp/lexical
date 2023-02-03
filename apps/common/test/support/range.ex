# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Range do
  alias Lexical.Protocol.Types.Position
  defstruct [:start, :end]

  def new(opts \\ []) do
    start = Keyword.get(opts, :start, Position.new())
    end_pos = Keyword.get(opts, :end, Position.new())
    %__MODULE__{start: start, end: end_pos}
  end
end
