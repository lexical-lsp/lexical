defmodule Lexical.Server.Window do
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Notifications.LogMessage
  alias Lexical.Protocol.Notifications.ShowMessage
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
  alias Lexical.Server.Transport

  @type level :: :error | :warning | :info | :log
  @type message_result :: {:errory, term()} | {:ok, nil} | {:ok, Types.Message.ActionItem.t()}
  @type on_response_callback :: (message_result() -> any())
  @type message :: String.t()
  @type action :: String.t()

  @levels [:error, :warning, :info, :log]

  @spec log(level, message()) :: :ok
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

  @spec show(level(), message()) :: :ok
  def show(level, message) when level in @levels and is_binary(message) do
    show_message = apply(ShowMessage, level, [message])
    Transport.write(show_message)
    :ok
  end

  @spec show_message(level(), message()) :: :ok
  def show_message(level, message) do
    request = Requests.ShowMessageRequest.new(id: Id.next(), message: message, type: level)
    Lexical.Server.server_request(request)
  end

  for level <- @levels,
      fn_name = :"show_#{level}_message" do
    def unquote(fn_name)(message) do
      show_message(unquote(level), message)
    end
  end

  for level <- @levels,
      fn_name = :"show_#{level}_message" do
    @doc """
    Shows a message at the #{level} level. Delegates to `show_message/4`
    """
    def unquote(fn_name)(message, actions, on_response) when is_function(on_response, 1) do
      show_message(unquote(level), message, actions, on_response)
    end
  end

  @doc """
  Shows a message request and handles the response

  Displays a message to the user in the UI and waits for a response.
  The result type handed to the callback function is a
  `Lexical.Protocol.Types.Message.ActionItem` or nil if there was no response
  from the user.

  The strings passed in as the `actions` command are displayed to the user, and when
  they select one, the `Types.Message.ActionItem` is passed to the callback function.
  """
  @spec show_message(level(), message(), [action()], on_response_callback) :: :ok
  def show_message(level, message, actions, on_response)
      when is_function(on_response, 1) do
    action_items =
      Enum.map(actions, fn action_string ->
        Types.Message.ActionItem.new(title: action_string)
      end)

    request =
      Requests.ShowMessageRequest.new(
        id: Id.next(),
        message: message,
        actions: action_items,
        type: level
      )

    Lexical.Server.server_request(request, fn _request, response -> on_response.(response) end)
  end
end
