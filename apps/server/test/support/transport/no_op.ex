defmodule Lexical.Test.Transport.NoOp do
  @behaviour Lexical.Server.Transport

  def write(_message, _opts \\ []), do: :ok
end
