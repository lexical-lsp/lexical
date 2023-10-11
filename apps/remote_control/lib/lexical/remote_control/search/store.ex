defmodule Lexical.RemoteControl.Search.Store do
  @moduledoc """
  A persistent store for search entries
  """

  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store
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

  @backend Application.compile_env(:remote_control, :search_store_backend, Store.Backends.Ets)
  @flush_interval_ms Application.compile_env(
                       :remote_control,
                       :search_store_quiescent_period_ms,
                       2500
                     )

  use GenServer
  require Logger
  import Messages

  def stop do
    #    GenServer.call(__MODULE__, :on_stop)
    GenServer.stop(__MODULE__)
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

  def destroy do
    GenServer.call(__MODULE__, :destroy)
  end

  @spec start_link(Project.t(), create_index, refresh_index, module()) :: GenServer.on_start()
  def start_link(%Project{} = project, create_index, refresh_index, backend) do
    GenServer.start_link(__MODULE__, [project, create_index, refresh_index, backend],
      name: __MODULE__
    )
  end

  def child_spec(init_args) when is_list(init_args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, normalize_init_args(init_args)}
    }
  end

  defp normalize_init_args([create_index, refresh_index]) do
    normalize_init_args([Lexical.RemoteControl.get_project(), create_index, refresh_index])
  end

  defp normalize_init_args([%Project{} = project, create_index, refresh_index]) do
    normalize_init_args([project, create_index, refresh_index, backend()])
  end

  defp normalize_init_args([%Project{}, create_index, refresh_index, backend] = args)
       when is_function(create_index, 1) and is_function(refresh_index, 2) and is_atom(backend) do
    args
  end

  @impl GenServer
  def init([%Project{} = project, create_index, update_index, backend]) do
    state =
      project
      |> State.new(create_index, update_index, backend)
      |> State.async_load()

    {:ok, {nil, state}}
  end

  @impl GenServer
  # handle the result from `State.async_load/1`
  def handle_info({ref, result}, {update_ref, %State{async_load_ref: ref} = state}) do
    RemoteControl.Dispatch.broadcast(index_ready(project: state.project))
    {:noreply, {update_ref, State.async_load_complete(state, result)}}
  end

  def handle_info(:flush_updates, {_, %State{} = state}) do
    {:ok, state} = State.flush_buffered_updates(state)
    ref = schedule_flush()
    {:noreply, {ref, state}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:replace, entities}, _from, {ref, %State{} = state}) do
    {reply, new_state} =
      case State.replace(state, entities) do
        {:ok, new_state} ->
          {:ok, State.drop_buffered_updates(new_state)}

        {:error, _} = error ->
          {error, state}
      end

    {:reply, reply, {ref, new_state}}
  end

  def handle_call({:exact, subject, constraints}, _from, {ref, %State{} = state}) do
    {:reply, State.exact(state, subject, constraints), {ref, state}}
  end

  def handle_call({:fuzzy, subject, constraints}, _from, {ref, %State{} = state}) do
    {:reply, State.fuzzy(state, subject, constraints), {ref, state}}
  end

  def handle_call(:all, _from, {ref, %State{} = state}) do
    {:reply, State.all(state), {ref, state}}
  end

  def handle_call({:update, path, entries}, _from, {ref, %State{} = state}) do
    {reply, new_ref, new_state} = do_update(state, ref, path, entries)

    {:reply, reply, {new_ref, new_state}}
  end

  def handle_call(:on_stop, _, {ref, %State{} = state}) do
    {:ok, state} = State.flush_buffered_updates(state)

    State.drop(state)
    {:reply, :ok, {ref, state}}
  end

  def handle_call(:loaded?, _, {ref, %State{loaded?: loaded?} = state}) do
    {:reply, loaded?, {ref, state}}
  end

  def handle_call(:destroy, _, {ref, %State{} = state}) do
    new_state = State.destroy(state)
    {:reply, :ok, {ref, new_state}}
  end

  @impl GenServer
  def terminate(_reason, {_, state}) do
    {:ok, state} = State.flush_buffered_updates(state)
    State.drop(state)
    {:noreply, state}
  end

  defp backend do
    @backend
  end

  defp do_update(state, old_ref, path, entries) do
    {:ok, schedule_flush(old_ref), State.buffer_updates(state, path, entries)}
  end

  defp schedule_flush(ref) when is_reference(ref) do
    Process.cancel_timer(ref)
    schedule_flush()
  end

  defp schedule_flush(_) do
    schedule_flush()
  end

  defp schedule_flush do
    Process.send_after(self(), :flush_updates, @flush_interval_ms)
  end
end
