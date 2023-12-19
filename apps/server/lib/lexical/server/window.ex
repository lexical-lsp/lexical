defmodule Lexical.Server.Window do
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Notifications.LogMessage
  alias Lexical.Protocol.Notifications.ShowMessage
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
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

  @spec show_message(String.t(), level()) :: :ok
  def show_message(message, message_type) do
    request = Requests.ShowMessageRequest.new(id: Id.next(), message: message, type: message_type)
    Lexical.Server.server_request(request)
  end

  @doc """
  Shows a message request and handles the response

  Displays a message to the user in the UI and waits for a response.
  The result type handed to the callback function is a
  `Lexical.Protocol.Types.Message.ActionItem` or nil if there was no response
  from the user.
  """
  @spec show_message(String.t(), level(), [String.t()], (any() -> any())) :: :ok
  def show_message(message, message_type, actions, on_response) do
    action_items =
      Enum.map(actions, fn action_string ->
        Types.Message.ActionItem.new(title: action_string)
      end)

    request =
      Requests.ShowMessageRequest.new(
        id: Id.next(),
        message: message,
        actions: action_items,
        type: message_type
      )

    Lexical.Server.server_request(request, fn _request, response -> on_response.(response) end)
  end
end
