defmodule Lexical.RemoteControl.Commands.Rename do
  # We are unable to accurately determine when the rename process finishes,
  # because after the rename, we will receive a series of events like
  # `DidChange`, `DidSave`, etc., which will trigger expensive actions like compiling the entire project.
  # Therefore, we need this module to tell us if lexical is currently in the process of renaming.

  alias Lexical.RemoteControl.Api.Messages
  import Messages

  defmodule State do
    defstruct uri_with_expected_operation: %{}, on_update_progess: nil, on_complete: nil

    def new(uri_with_expected_operation, progress_functions) do
      {on_update_progess, on_complete} = progress_functions

      %__MODULE__{
        uri_with_expected_operation: uri_with_expected_operation,
        on_update_progess: on_update_progess,
        on_complete: on_complete
      }
    end

    def update_progress(%__MODULE__{} = state, file_changed(uri: uri)) do
      update_progress(state, uri, file_changed(uri: uri))
    end

    def update_progress(%__MODULE__{} = state, file_saved(uri: uri)) do
      update_progress(state, uri, file_saved(uri: uri))
    end

    defp update_progress(%__MODULE__{} = state, uri, message) do
      new_uri_with_expected_operation =
        maybe_pop_expected_operation(
          state.uri_with_expected_operation,
          uri,
          message,
          state.on_update_progess
        )

      if new_uri_with_expected_operation == %{} do
        state.on_complete.()
      end

      %__MODULE__{state | uri_with_expected_operation: new_uri_with_expected_operation}
    end

    def in_progress?(%__MODULE__{} = state) do
      state.uri_with_expected_operation != %{}
    end

    def maybe_pop_expected_operation(uri_to_operation, uri, message, on_update_progess) do
      case uri_to_operation do
        %{^uri => ^message} ->
          on_update_progess.(1, "")
          Map.delete(uri_to_operation, uri)

        _ ->
          uri_to_operation
      end
    end
  end

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @spec set_rename_progress(
          %{Lexical.uri() => Messages.file_changed() | Messages.file_saved()},
          {function(), function()}
        ) :: :ok
  def set_rename_progress(uri_with_expected_operation, progress_functions) do
    GenServer.cast(
      __MODULE__,
      {:set_rename_progress, uri_with_expected_operation, progress_functions}
    )
  end

  def in_progress? do
    GenServer.call(__MODULE__, :in_progress?)
  end

  @spec update_progress(Messages.file_changed() | Messages.file_saved()) :: :ok
  # NOTE:
  # This GenServer cannot simply subscribe to messages and then update the rename status.
  # Instead, it should call this function to synchronously update the status,
  # thus preventing failures due to latency issues.
  def update_progress(message) do
    GenServer.cast(__MODULE__, {:update_progress, message})
  end

  @impl true
  def handle_call(:in_progress?, _from, state) do
    {:reply, State.in_progress?(state), state}
  end

  @impl true
  def handle_cast({:update_progress, message}, state) do
    new_state = State.update_progress(state, message)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_rename_progress, uri_with_expected_operation, progress_functions}, _state) do
    new_state = State.new(uri_with_expected_operation, progress_functions)
    {:noreply, new_state}
  end
end
