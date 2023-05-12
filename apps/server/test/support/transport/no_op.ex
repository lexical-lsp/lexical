defmodule Lexical.Test.Transport.NoOp do
  @behaviour Lexical.Server.Transport

  def write(_message), do: :ok
  def log(_level, _message), do: :ok
end
