defmodule Lexical.Server.Window do
  alias Lexical.Protocol.Notifications.LogMessage
  alias Lexical.Protocol.Notifications.ShowMessage
  alias Lexical.Server.Transport

  @type level :: :error | :warning | :info | :log

  @levels [:error, :warning, :info, :log]

  @spec log(level, String.t()) :: :ok
  def log(level, message) when level in @levels and is_binary(message) do
    log_message = apply(LogMessage, level, [message])
    Transport.write(log_message)
    :ok
  end

  for level <- [:error, :warning, :info] do
    def unquote(level)(message) do
      log(unquote(level), message)
    end
  end

  @spec show(level, String.t()) :: :ok
  def show(level, message) when level in @levels and is_binary(message) do
    show_message = apply(ShowMessage, level, [message])
    Transport.write(show_message)
    :ok
  end
end
