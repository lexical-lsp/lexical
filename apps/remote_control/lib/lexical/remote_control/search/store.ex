defmodule Lexical.RemoteControl.Search.Store do
  @moduledoc """
  A persistent store for search entries
  """

  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.State

  use GenServer

  def stop do
    GenServer.stop(__MODULE__)
  end

  def schema do
    GenServer.call(__MODULE__, :schema)
  end

  def all do
    GenServer.call(__MODULE__, :all)
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

  def update(path, entries) do
    GenServer.call(__MODULE__, {:update, path, entries})
  end

  def start_link([%Project{} = project, indexer_fn]) do
    GenServer.start_link(__MODULE__, [project, indexer_fn], name: __MODULE__)
  end

  def init([%Project{} = project, index_fn]) do
    state = State.new(project, index_fn)

    {:ok, state, {:continue, :load}}
  end

  def handle_continue(:load, %State{} = state) do
    {:ok, state} = State.load(state)
    {:noreply, state}
  end

  def handle_call(:load, _, %State{} = state) do
    {reply, new_state} =
      case State.load(state) do
        {:ok, new_state} ->
          {:ok, new_state}

        {error, new_state} ->
          {error, new_state}
      end

    {:reply, reply, new_state}
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

  def handle_call(:schema, _from, %State{} = state) do
    {reply, new_state} =
      case State.schema(state) do
        {:ok, schema, state} ->
          {schema, state}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end
end
