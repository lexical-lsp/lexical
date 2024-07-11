defmodule Lexical.Server do
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Server.State
  alias Lexical.Server.TaskQueue

  require Logger

  use GenServer

  @server_specific_messages [
    Notifications.DidChange,
    Notifications.DidChangeConfiguration,
    Notifications.DidChangeWatchedFiles,
    Notifications.DidClose,
    Notifications.DidOpen,
    Notifications.DidSave,
    Notifications.Exit,
    Notifications.Initialized,
    Requests.Shutdown
  ]

  @dialyzer {:nowarn_function, apply_to_state: 2}

  @spec server_request(
          Requests.request(),
          (Requests.request(), {:ok, any()} | {:error, term()} -> term())
        ) :: :ok
  def server_request(request, on_response) when is_function(on_response, 2) do
    GenServer.call(__MODULE__, {:server_request, request, on_response})
  end

  @spec server_request(Requests.request()) :: :ok
  def server_request(request) do
    server_request(request, fn _, _ -> :ok end)
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

  def handle_call({:server_request, request, on_response}, _from, %State{} = state) do
    new_state = State.add_request(state, request, on_response)
    {:reply, :ok, new_state}
  end

  def handle_cast({:protocol_message, message}, %State{} = state) do
    new_state =
      case handle_message(message, state) do
        {:ok, new_state} ->
          new_state

        error ->
          Logger.error(
            "Could not handle message #{inspect(message.__struct__)} #{inspect(error)}"
          )

          state
      end

    {:noreply, new_state}
  end

  def handle_cast(other, %State{} = state) do
    Logger.info("got other: #{inspect(other)}")
    {:noreply, state}
  end

  def handle_info(:default_config, %State{configuration: nil} = state) do
    Logger.warning(
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
    TaskQueue.cancel(cancel_request)
    {:ok, state}
  end

  def handle_message(%Notifications.Cancel{} = cancel_notification, %State{} = state) do
    TaskQueue.cancel(cancel_notification)
    {:ok, state}
  end

  def handle_message(%message_module{} = message, %State{} = state)
      when message_module in @server_specific_messages do
    case apply_to_state(state, message) do
      {:ok, _} = success ->
        success

      error ->
        Logger.error("Failed to handle #{message.__struct__}, #{inspect(error)}")
    end
  end

  def handle_message(nil, %State{} = state) do
    # NOTE: This deals with the response after a request is requested by the server,
    # such as the response of `CreateWorkDoneProgress`.
    {:ok, state}
  end

  def handle_message(%_{} = request, %State{} = state) do
    with {:ok, handler} <- fetch_handler(request),
         {:ok, req} <- Convert.to_native(request) do
      TaskQueue.add(request.id, {handler, :handle, [req, state.configuration]})
    else
      {:error, {:unhandled, _}} ->
        Logger.info("Unhandled request: #{request.method}")

      _ ->
        :ok
    end

    {:ok, state}
  end

  def handle_message(%{} = response, %State{} = state) do
    new_state = State.finish_request(state, response)

    {:ok, new_state}
  end

  defp apply_to_state(%State{} = state, %{} = request_or_notification) do
    case State.apply(state, request_or_notification) do
      {:ok, new_state} -> {:ok, new_state}
      :ok -> {:ok, state}
      error -> {error, state}
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp fetch_handler(%_{} = request) do
    case request do
      %Requests.FindReferences{} ->
        {:ok, Handlers.FindReferences}

      %Requests.Formatting{} ->
        {:ok, Handlers.Formatting}

      %Requests.CodeAction{} ->
        {:ok, Handlers.CodeAction}

      %Requests.CodeLens{} ->
        {:ok, Handlers.CodeLens}

      %Requests.Completion{} ->
        {:ok, Handlers.Completion}

      %Requests.GoToDefinition{} ->
        {:ok, Handlers.GoToDefinition}

      %Requests.Hover{} ->
        {:ok, Handlers.Hover}

      %Requests.ExecuteCommand{} ->
        {:ok, Handlers.Commands}

      %Requests.DocumentSymbols{} ->
        {:ok, Handlers.DocumentSymbols}

      %Requests.WorkspaceSymbol{} ->
        {:ok, Handlers.WorkspaceSymbol}

      %request_module{} ->
        {:error, {:unhandled, request_module}}
    end
  end
end
