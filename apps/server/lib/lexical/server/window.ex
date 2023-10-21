defmodule Lexical.Server.Window do
  alias Lexical.Protocol.Notifications.LogMessage
  alias Lexical.Protocol.Notifications.ShowMessage
  alias Lexical.Server.Transport

  @type level :: :error | :warning | :info | :log

  @spec log(level, String.t()) :: String.t()
  def log(level, message) when level in [:error, :warning, :info, :log] do
    log_message = apply(LogMessage, level, [message])
    Transport.write(log_message)
    message
  end

  for level <- [:error, :warning, :info] do
    def unquote(level)(message) do
      log(unquote(level), message)
    end
  end

  @spec show(level, String.t()) :: String.t()
  def show(level, message) do
    show_message = apply(ShowMessage, level, [message])
    Transport.write(show_message)
    message
  end
end
