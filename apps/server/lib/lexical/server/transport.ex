defmodule Lexical.Server.Transport do
  alias Lexical.Server.Transport.StdIO

  defdelegate log(level, message), to: StdIO
  defdelegate write(messaeg), to: StdIO

  def error(message) do
    StdIO.log(:error, message)
  end
end
