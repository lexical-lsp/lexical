defmodule Lexical.Transport.StdIO do
  alias Lexical.Server
  alias Lexical.Protocol.Notifications

  @crlf "\r\n"

  defdelegate write(device, payload), to: Lexical.Server.IOServer
  defdelegate write(payload), to: Lexical.Server.IOServer
  defdelegate log(level, payload), to: Lexical.Server.IOServer

  def error(message_text) do
    log(:error, message_text)
  end
end
