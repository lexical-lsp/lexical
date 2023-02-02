defmodule Lexical.Transport do
  alias Lexical.Server.IOServer

  def log(level \\ :error, message)

  def log(level, message) do
    IOServer.log(level, message)
  end

  def write(message) do
    IOServer.write(message)
  end
end
