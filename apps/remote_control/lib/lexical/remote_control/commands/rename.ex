defmodule Lexical.RemoteControl.Commands.Rename do
  @moduledoc """
  We are unable to accurately determine the process of renaming,
  because after the rename, there will be a series of operations such as
  `DidChange`, `DidSave`, etc., which will trigger expensive actions like compiling the entire project.
  Therefore, we need this module to make some markings to determine whether it is currently in the process of renaming.
  """
  defmodule State do
    defstruct uri_with_operation_counts: %{}

    def new(uri_with_operation_counts) do
      %__MODULE__{uri_with_operation_counts: uri_with_operation_counts}
    end

    def mark_changed(%__MODULE__{} = state, uri) do
      new_uri_with_operation_counts =
        delete_key_or_reduce_counts(state.uri_with_operation_counts, uri)

      %__MODULE__{state | uri_with_operation_counts: new_uri_with_operation_counts}
    end

    def mark_saved(%__MODULE__{} = state, uri) do
      new_uri_with_operation_counts =
        delete_key_or_reduce_counts(state.uri_with_operation_counts, uri)

      %__MODULE__{state | uri_with_operation_counts: new_uri_with_operation_counts}
    end

    def mark_closed(%__MODULE__{} = state, uri) do
      new_uri_with_operation_counts =
        delete_key_or_reduce_counts(state.uri_with_operation_counts, uri)

      %__MODULE__{state | uri_with_operation_counts: new_uri_with_operation_counts}
    end

    def in_progress?(%__MODULE__{} = state) do
      state.uri_with_operation_counts != %{}
    end

    defp delete_key_or_reduce_counts(uri_with_operation_counts, uri) do
      {_, new_map} =
        Map.get_and_update(uri_with_operation_counts, uri, fn
          nil -> :pop
          current_counts when current_counts <= 1 -> :pop
          current_counts -> {current_counts, current_counts - 1}
        end)

      new_map
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

  def set_rename_progress(uri_with_operation_counts) do
    GenServer.cast(__MODULE__, {:set_rename_progress, uri_with_operation_counts})
  end

  def mark_changed(uri) do
    GenServer.cast(__MODULE__, {:mark_changed, uri})
  end

  @doc """
  When a rename is completed, the old file will be closed.
  """
  def mark_closed(uri) do
    GenServer.cast(__MODULE__, {:mark_closed, uri})
  end

  @doc """
  When a rename is completed, the new file will be saved.
  """
  def mark_saved(uri) do
    GenServer.cast(__MODULE__, {:mark_saved, uri})
  end

  def in_progress? do
    GenServer.call(__MODULE__, :in_progress?)
  end

  @impl true
  def handle_call(:in_progress?, _from, state) do
    {:reply, State.in_progress?(state), state}
  end

  @impl true
  def handle_cast({:set_rename_progress, uri_with_operation_counts}, _state) do
    new_state = State.new(uri_with_operation_counts)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mark_changed, uri}, %State{} = state) do
    new_state = State.mark_changed(state, uri)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mark_saved, uri}, %State{} = state) do
    new_state = State.mark_saved(state, uri)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mark_closed, uri}, %State{} = state) do
    new_state = State.mark_closed(state, uri)
    {:noreply, new_state}
  end
end
