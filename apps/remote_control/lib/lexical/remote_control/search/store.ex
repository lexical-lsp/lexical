defmodule Lexical.RemoteControl.Search.Store do
  @moduledoc """
  A persistent store for search entries
  """

  alias Lexical.Project
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.Dispatch
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

  import Api.Messages
  use GenServer
  require Logger

  def stop do
    GenServer.stop(__MODULE__)
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

  def prefix(prefix, constraints) do
    GenServer.call(__MODULE__, {:prefix, prefix, constraints})
  end

  def parent(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:parent, entry})
  end

  def siblings(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:siblings, entry})
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

  def enable do
    GenServer.call(__MODULE__, :enable)
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
    Process.flag(:fullsweep_after, 5)
    schedule_gc()
    # I've found that if indexing happens before the first compile, for some reason
    # the compilation is 4x slower than if indexing happens after it. I was
    # unable to figure out why this is the case, and I looked extensively, so instead
    # we have this bandaid. We wait for the first compilation to complete, and then
    # the search store enables itself, at which point we index the code.

    Dispatch.register_listener(self(), project_compiled())
    state = State.new(project, create_index, update_index, backend)
    {:ok, state}
  end

  @impl GenServer
  # enable ourselves when the project is force compiled
  def handle_info(project_compiled(), %State{} = state) do
    {:noreply, enable(state)}
  end

  def handle_info(project_compiled(), {_, _} = state) do
    # we're already enabled, no need to do anything
    {:noreply, state}
  end

  # handle the result from `State.async_load/1`
  def handle_info({ref, result}, {update_ref, %State{async_load_ref: ref} = state}) do
    {:noreply, {update_ref, State.async_load_complete(state, result)}}
  end

  def handle_info(:flush_updates, {_, %State{} = state}) do
    {:ok, state} = State.flush_buffered_updates(state)
    ref = schedule_flush()
    {:noreply, {ref, state}}
  end

  def handle_info(:gc, state) do
    :erlang.garbage_collect()
    schedule_gc()
    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:enable, _from, %State{} = state) do
    {:reply, :ok, enable(state)}
  end

  def handle_call(:enable, _from, state) do
    {:reply, :ok, state}
  end

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

  def handle_call({:prefix, prefix, constraints}, _from, {ref, %State{} = state}) do
    {:reply, State.prefix(state, prefix, constraints), {ref, state}}
  end

  def handle_call({:fuzzy, subject, constraints}, _from, {ref, %State{} = state}) do
    {:reply, State.fuzzy(state, subject, constraints), {ref, state}}
  end

  def handle_call({:update, path, entries}, _from, {ref, %State{} = state}) do
    {reply, new_ref, new_state} = do_update(state, ref, path, entries)

    {:reply, reply, {new_ref, new_state}}
  end

  def handle_call({:parent, entry}, _from, {_, %State{} = state} = orig_state) do
    parent = State.parent(state, entry)
    {:reply, parent, orig_state}
  end

  def handle_call({:siblings, entry}, _from, {_, %State{} = state} = orig_state) do
    siblings = State.siblings(state, entry)
    {:reply, siblings, orig_state}
  end

  def handle_call(:on_stop, _, {ref, %State{} = state}) do
    {:ok, state} = State.flush_buffered_updates(state)

    State.drop(state)
    {:reply, :ok, {ref, state}}
  end

  def handle_call(:loaded?, _, {ref, %State{loaded?: loaded?} = state}) do
    {:reply, loaded?, {ref, state}}
  end

  def handle_call(:loaded?, _, %State{loaded?: loaded?} = state) do
    # We're not enabled yet, but we can still reply to the query
    {:reply, loaded?, state}
  end

  def handle_call(:destroy, _, {ref, %State{} = state}) do
    new_state = State.destroy(state)
    {:reply, :ok, {ref, new_state}}
  end

  def handle_call(message, _from, %State{} = state) do
    Logger.warning("Received #{inspect(message)}, but the search store isn't enabled yet.")
    {:reply, {:error, {:not_enabled, message}}, state}
  end

  @impl GenServer
  def terminate(_reason, {_, state}) do
    {:ok, state} = State.flush_buffered_updates(state)
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

  defp enable(%State{} = state) do
    state = State.async_load(state)
    {nil, state}
  end

  defp schedule_gc do
    Process.send_after(self(), :gc, :timer.seconds(5))
  end
end
