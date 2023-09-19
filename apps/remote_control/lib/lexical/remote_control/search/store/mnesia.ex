defmodule Lexical.RemoteControl.Search.Store.Mnesia do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.Backend
  alias Lexical.RemoteControl.Search.Store.Mnesia.Query
  alias Lexical.RemoteControl.Search.Store.Mnesia.Schema
  alias Lexical.RemoteControl.Search.Store.Mnesia.State

  use GenServer

  @behaviour Backend

  @impl Backend
  defdelegate drop(), to: Query

  def config do
    Application.get_env(:remote_control, __MODULE__, [])
  end

  def set_persist_to_disc(persist?) do
    config = Keyword.put(config(), :persist_to_disc, persist?)
    Application.put_env(:remote_control, Mnesia, config)
  end

  def persist_to_disc? do
    Keyword.get(config(), :persist_to_disc, true)
  end

  @impl Backend
  def sync(_) do
    :ok
  end

  @impl Backend
  def destroy(_) do
    Query.drop()
    :ok
  end

  @impl Backend
  def new(%Project{} = project) do
    start_link(project)
  end

  # Note: we need to go through the genserver to ensure mnesia has started
  # and that the tables are ready. Drop is special because it's often called
  # in unit tests after the genserver has stopped
  @impl Backend
  def delete_by_path(path) do
    GenServer.call(__MODULE__, {:delete_by_path, path})
  end

  @impl Backend
  def prepare(_backend_pid) do
    with :ok <- wait_for_start() do
      {:ok, Schema.load_state()}
    end
  end

  @impl Backend
  def select_all do
    GenServer.call(__MODULE__, :select_all)
  end

  @impl Backend
  def find_by_refs(references, type, subtype) do
    GenServer.call(__MODULE__, {:find_by_refs, references, type, subtype})
  end

  @impl Backend
  def find_by_subject(subject, type, subtype) do
    GenServer.call(__MODULE__, {:find_by_subject, subject, type, subtype})
  end

  @impl Backend
  def insert(entries) do
    GenServer.call(__MODULE__, {:insert, entries})
  end

  @impl Backend
  def replace_all(entries) do
    GenServer.call(__MODULE__, {:replace_all, entries})
  end

  def wait_for_start do
    GenServer.call(__MODULE__, :wait_for_start)
  end

  def initial_state do
    GenServer.call(__MODULE__, :initial_state)
  end

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: __MODULE__)
  end

  @impl GenServer
  def init([%Project{} = project]) do
    {:ok, State.new(project), {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, %State{} = state) do
    new_state = State.ensure_node_exists(state)

    {:noreply, new_state, {:continue, :connect_to_node}}
  end

  def handle_continue(:connect_to_node, %State{} = state) do
    case State.connect_to_node(state) do
      {:connected, new_state} ->
        {:noreply, new_state}

      {:connect_to_node, new_state} ->
        {:noreply, new_state, {:continue, :connect_to_node}}
    end
  end

  @impl GenServer
  def handle_call({:delete_by_path, path}, _from, %State{} = state) do
    reply = Query.delete_by_path(path)
    {:reply, reply, state}
  end

  def handle_call(:drop, _from, %State{} = state) do
    reply = Query.drop()
    {:reply, reply, state}
  end

  def handle_call({:find_by_refs, references, type, subtype}, _from, %State{} = state) do
    reply = Query.find_by_refs(references, type, subtype)
    {:reply, reply, state}
  end

  def handle_call(:select_all, _from, %State{} = state) do
    reply = Query.select_all()
    {:reply, reply, state}
  end

  def handle_call({:replace_all, entries}, _from, %State{} = state) do
    reply = Query.replace_all(entries)
    {:reply, reply, state}
  end

  def handle_call({:find_by_subject, subject, type, subtype}, _from, %State{} = state) do
    reply = Query.find_by_subject(subject, type, subtype)
    {:reply, reply, state}
  end

  def handle_call({:insert, entries}, _from, %State{} = state) do
    reply = Query.insert(entries)
    {:reply, reply, state}
  end

  def handle_call(:wait_for_start, _from, %State{} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:destroy, _from, %State{} = state) do
    Schema.destroy()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({port, {:data, _}}, %State{} = state) when is_port(port) do
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, %State{} = state) do
    {:connect_to_node, state} = State.on_nodedown(state, node)
    {:noreply, state, {:continue, :connect}}
  end

  def handle_info({:DOWN, port_ref, :port, _, _reason}, %State{} = state) do
    {:connect_to_node, state} = State.on_port_closed(state, port_ref)
    {:noreply, state, {:continue, :connect}}
  end
end
