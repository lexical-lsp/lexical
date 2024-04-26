defmodule Lexical.RemoteControl.Commands.Rename do
  @moduledoc """
  We are unable to accurately determine the process of renaming,
  because after the rename, there will be a series of operations such as
  `DidChange`, `DidSave`, etc., which will trigger expensive actions like compiling the entire project.
  Therefore, we need this module to make some markings to determine whether it is currently in the process of renaming.
  """
  defmodule State do
    defstruct uri_with_expected_operation: %{}

    def new(uri_with_expected_operation) do
      %__MODULE__{uri_with_expected_operation: uri_with_expected_operation}
    end

    def update_progress(%__MODULE__{} = state, uri, operation_message) do
      new_uri_with_expected_operation =
        maybe_pop_expected_operation(state.uri_with_expected_operation, uri, operation_message)

      %__MODULE__{state | uri_with_expected_operation: new_uri_with_expected_operation}
    end

    def in_progress?(%__MODULE__{} = state) do
      state.uri_with_expected_operation != %{}
    end

    def maybe_pop_expected_operation(uri_to_operation, uri, %operation{}) do
      case uri_to_operation do
        %{^uri => ^operation} -> Map.delete(uri_to_operation, uri)
        _ -> uri_to_operation
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

  @spec set_rename_progress(%{Lexical.uri() => atom()}) :: :ok
  def set_rename_progress(uri_with_expected_operation) do
    GenServer.cast(__MODULE__, {:set_rename_progress, uri_with_expected_operation})
  end

  def update_progress(uri, operation_message) do
    GenServer.cast(__MODULE__, {:update_progress, uri, operation_message})
  end

  def in_progress? do
    GenServer.call(__MODULE__, :in_progress?)
  end

  @impl true
  def handle_call(:in_progress?, _from, state) do
    {:reply, State.in_progress?(state), state}
  end

  @impl true
  def handle_cast({:set_rename_progress, uri_with_expected_operation}, _state) do
    new_state = State.new(uri_with_expected_operation)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_progress, uri, message}, state) do
    new_state = State.update_progress(state, uri, message)
    {:noreply, new_state}
  end
end
