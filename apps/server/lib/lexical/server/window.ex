defmodule Lexical.Server.Window do
  alias Lexical.Protocol.Notifications.LogMessage
  alias Lexical.Protocol.Notifications.ShowMessage
  alias Lexical.Server.Transport

  @type level :: :error | :warning | :info | :log

  @spec log(level, String.t(), [{:label, String.t()}]) :: String.t()
  def log(level, message, opts \\ [])

  def log(level, message, opts) when level in [:error, :warning, :info, :log] do
    formatted_message = format_message(message, opts)
    log_message = apply(LogMessage, level, [formatted_message])
    Transport.write(log_message)
    message
  end

  def log(_level, message, opts) do
    log_message = format_message(message, opts)
    Transport.write(log_message, io_device: :standard_error)
    message
  end

  @spec show(level, String.t()) :: String.t()
  def show(level, message) do
    show_message = apply(ShowMessage, level, [message])
    Transport.write(show_message)
    message
  end

  defp format_message(message, opts) do
    case Keyword.get(opts, :label) do
      nil -> inspect(message) <> "\n"
      label -> "#{label}: '#{inspect(message, limit: :infinity)}\n"
    end
  end
end
