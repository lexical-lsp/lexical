defmodule Lexical.RemoteControl.Search.Store do
  @moduledoc """
  A persistent store for search entries
  """

  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.State

  @type index_state :: :empty | :stale
  @type existing_entries :: [Entry.t()]
  @type new_entries :: [Entry.t()]
  @type updated_entries :: [Entry.t()]
  @type paths_to_delete :: [Path.t()]
  @typedoc """
  A function that creates indexes when none is detected
  """
  @type create_index ::
          (project :: Project.t() ->
             {:ok, new_entries} | {:error, term()})

  @typedoc """
  A function that takes existing entries and refreshes them if necessary
  """
  @type refresh_index ::
          (project :: Project.t(), entries :: existing_entries ->
             {:ok, new_entries, paths_to_delete} | {:error, term()})

  use GenServer
  require Logger

  def stop do
    GenServer.call(__MODULE__, :drop)
    GenServer.stop(__MODULE__)
  end

  def metadata do
    GenServer.call(__MODULE__, :metadata)
  end

  def all do
    GenServer.call(__MODULE__, :all)
  end

  def loaded? do
    GenServer.call(__MODULE__, :loaded?)
  end

  def replace(entries) do
    GenServer.call(__MODULE__, {:replace, entries})
  end

  def exact(subject \\ :_, constraints) do
    GenServer.call(__MODULE__, {:exact, subject, constraints})
  end

  def fuzzy(subject, constraints) do
    GenServer.call(__MODULE__, {:fuzzy, subject, constraints})
  end

  def clear(path) do
    GenServer.call(__MODULE__, {:update, path, []})
  end

  def update(path, entries) do
    GenServer.call(__MODULE__, {:update, path, entries})
  end

  def unique_fields(fields) do
    GenServer.call(__MODULE__, {:unique_fields, fields})
  end

  @spec start_link(Project.t(), create_index, refresh_index) :: GenServer.on_start()
  def start_link(%Project{} = project, create_index, refresh_index) do
    start_link([project, create_index, refresh_index])
  end

  def start_link([%Project{} = project, create_index, refresh_index]) do
    GenServer.start_link(__MODULE__, [project, create_index, refresh_index], name: __MODULE__)
  end

  def start_link([create_index, refresh_index]) do
    start_link(Lexical.RemoteControl.get_project(), create_index, refresh_index)
  end

  def init([%Project{} = project, create_index, update_index]) do
    state =
      project
      |> State.new(create_index, update_index)
      |> State.async_load()

    {:ok, state}
  end

  # handle the result from `State.async_load/1`
  def handle_info({ref, result}, %State{async_load_ref: ref} = state) do
    {:noreply, State.async_load_complete(state, result)}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def handle_call({:replace, entities}, _from, %State{} = state) do
    {reply, new_state} =
      case State.replace(state, entities) do
        {:ok, new_state} ->
          {:ok, new_state}

        {:error, _} = error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:exact, subject, constraints}, _from, %State{} = state) do
    {:reply, State.exact(state, subject, constraints), state}
  end

  def handle_call({:fuzzy, subject, constraints}, _from, %State{} = state) do
    {:reply, State.fuzzy(state, subject, constraints), state}
  end

  def handle_call(:all, _from, %State{} = state) do
    {:reply, State.all(state), state}
  end

  def handle_call({:update, path, entries}, _from, %State{} = state) do
    {reply, new_state} =
      case State.update(state, path, entries) do
        {:ok, new_state} ->
          {:ok, new_state}

        {:error, _} = error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call(:metadata, _from, %State{} = state) do
    {reply, new_state} =
      case State.metadata(state) do
        {:ok, metadata, state} ->
          {metadata, state}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:unique_fields, fields}, _from, %State{} = state) do
    {reply, new_state} =
      case State.unique_fields(state, fields) do
        {:ok, entries, new_state} ->
          {entries, new_state}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call(:drop, _, %State{} = state) do
    State.drop(state)
    {:reply, :ok, state}
  end

  def handle_call(:loaded?, _, %State{loaded?: loaded?} = state) do
    {:reply, loaded?, state}
  end
end
