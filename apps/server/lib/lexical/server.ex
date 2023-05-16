defmodule Lexical.Server do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Server.Provider
  alias Lexical.Server.State

  import Logger

  use GenServer

  @server_specific_messages [
    Notifications.DidChange,
    Notifications.DidChangeConfiguration,
    Notifications.DidClose,
    Notifications.DidOpen,
    Notifications.DidSave,
    Notifications.Exit,
    Notifications.Initialized,
    Requests.Shutdown
  ]

  @dialyzer {:nowarn_function, handle_cast: 2}

  @spec response_complete(Requests.request(), Responses.response()) :: :ok
  def response_complete(request, response) do
    GenServer.call(__MODULE__, {:response_complete, request, response})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def protocol_message(message) do
    GenServer.cast(__MODULE__, {:protocol_message, message})
  end

  def init(_) do
    {:ok, State.new()}
  end

  def handle_call({:response_complete, _request, _response}, _from, %State{} = state) do
    {:reply, :ok, state}
  end

  def handle_cast({:protocol_message, message}, %State{} = state) do
    new_state =
      case handle_message(message, state) do
        :ok ->
          state

        {:ok, new_state} ->
          new_state

        error ->
          error("Could not handle message #{inspect(message.__struct__)} #{inspect(error)}")
          state
      end

    {:noreply, new_state}
  end

  def handle_cast(other, %State{} = state) do
    info("got other: #{inspect(other)}")
    {:noreply, state}
  end

  def handle_info(:default_config, %State{configuration: nil} = state) do
    warn(
      "Did not receive workspace/didChangeConfiguration notification after 5 seconds. " <>
        "Using default settings."
    )

    {:ok, config} = State.default_configuration(state)
    {:noreply, %State{state | configuration: config}}
  end

  def handle_info(:default_config, %State{} = state) do
    {:noreply, state}
  end

  def handle_message(%Requests.Initialize{} = initialize, %State{} = state) do
    Process.send_after(self(), :default_config, :timer.seconds(5))

    case State.initialize(state, initialize) do
      {:ok, _state} = success ->
        success

      error ->
        {error, state}
    end
  end

  def handle_message(%Requests.Cancel{} = cancel_request, %State{} = state) do
    Provider.Queue.cancel(cancel_request)
    {:ok, state}
  end

  def handle_message(%Notifications.Cancel{} = cancel_notification, %State{} = state) do
    Provider.Queue.cancel(cancel_notification)
    {:ok, state}
  end

  def handle_message(%message_module{} = message, %State{} = state)
      when message_module in @server_specific_messages do
    State.apply(state, message)
  end

  def handle_message(nil, %State{} = state) do
    # NOTE: This deals with the response after a request is requested by the server,
    # such as the response of workDoneProgress.
    {:ok, state}
  end

  def handle_message(request, %State{} = state) do
    Provider.Queue.add(request, state.configuration)

    {:ok, state}
  end
end
