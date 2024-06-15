defmodule Lexical.RemoteControl.Commands.Rename do
  # We are unable to accurately determine when the rename process finishes,
  # because after the rename, we will receive a series of events like
  # `DidChange`, `DidSave`, etc., which will trigger expensive actions like compiling the entire project.
  # Therefore, we need this module to tell us if lexical is currently in the process of renaming.

  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Commands.Reindex
  require Logger
  import Messages

  defmodule State do
    @type uri_to_expected_operation :: %{
            Lexical.uri() => Messages.file_changed() | Messages.file_saved()
          }

    @type t :: %__MODULE__{
            uri_to_expected_operation: uri_to_expected_operation(),
            raw_uri_to_expected_operation: uri_to_expected_operation(),
            on_update_progess: fun(),
            on_complete: fun()
          }
    defstruct uri_to_expected_operation: %{},
              raw_uri_to_expected_operation: %{},
              on_update_progess: nil,
              on_complete: nil

    def new(uri_to_expected_operation, on_update_progess, on_complete) do
      %__MODULE__{
        uri_to_expected_operation: uri_to_expected_operation,
        raw_uri_to_expected_operation: uri_to_expected_operation,
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
          state.uri_to_expected_operation,
          uri,
          message,
          state.on_update_progess
        )

      if Enum.empty?(new_uri_with_expected_operation) do
        state.on_complete.()
        reindex_all_renamed_files(state)
      end

      %__MODULE__{state | uri_to_expected_operation: new_uri_with_expected_operation}
    end

    def in_progress?(%__MODULE__{} = state) do
      state.uri_to_expected_operation != %{}
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

    defp reindex_all_renamed_files(%__MODULE__{} = state) do
      state.raw_uri_to_expected_operation
      |> Map.keys()
      |> Enum.each(&Reindex.uri/1)
    end
  end

  alias Lexical.RemoteControl.Api.Proxy
  use GenServer

  @spec child_spec(
          %{Lexical.uri() => Messages.file_changed() | Messages.file_saved()},
          fun(),
          fun()
        ) :: Supervisor.child_spec()
  def child_spec(uri_to_expected_operation, on_update_progess, on_complete) do
    %{
      id: __MODULE__,
      start:
        {__MODULE__, :start_link, [uri_to_expected_operation, on_update_progess, on_complete]},
      restart: :transient
    }
  end

  def start_link(uri_to_expected_operation, on_update_progess, on_complete) do
    state = State.new(uri_to_expected_operation, on_update_progess, on_complete)
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :start_buffering}}
  end

  @spec update_progress(Messages.file_changed() | Messages.file_saved()) :: :ok
  # NOTE:
  # This GenServer cannot simply subscribe to messages and then update the rename status.
  # Instead, it should call this function to synchronously update the status,
  # thus preventing failures due to latency issues.
  def update_progress(message) do
    pid = Process.whereis(__MODULE__)

    if pid && Process.alive?(pid) do
      GenServer.cast(__MODULE__, {:update_progress, message})
    else
      {:error, :not_in_rename_progress}
    end
  end

  @impl true
  def handle_continue(:start_buffering, state) do
    Proxy.start_buffering()
    {:noreply, state}
  end

  @impl true
  def handle_call(:in_progress?, _from, state) do
    {:reply, State.in_progress?(state), state}
  end

  @impl true
  def handle_cast({:update_progress, message}, state) do
    new_state = State.update_progress(state, message)

    if State.in_progress?(new_state) do
      {:noreply, new_state}
    else
      Logger.info("Rename process completed.")
      {:stop, :normal, new_state}
    end
  end
end
