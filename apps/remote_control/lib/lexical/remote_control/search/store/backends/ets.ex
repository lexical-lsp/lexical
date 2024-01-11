defmodule Lexical.RemoteControl.Search.Store.Backends.Ets do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backend
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.State

  use GenServer

  @behaviour Backend

  @impl Backend
  def new(%Project{} = project) do
    start_link(project)
  end

  @impl Backend
  def prepare(pid) do
    GenServer.call(pid, :prepare, :infinity)
  end

  @impl Backend
  def sync(%Project{}) do
    GenServer.call(genserver_name(), :sync)
  end

  @impl Backend
  def insert(entries) do
    GenServer.call(genserver_name(), {:insert, [entries]}, :infinity)
  end

  @impl Backend
  def drop do
    GenServer.call(genserver_name(), {:drop, []})
  end

  @impl Backend
  def destroy(%Project{} = project) do
    name = genserver_name(project)

    case :global.whereis_name(name) do
      pid when is_pid(pid) ->
        GenServer.call(name, {:destroy, []})

      _ ->
        State.destroy(project)
    end

    :ok
  end

  @impl Backend
  def select_all do
    GenServer.call(genserver_name(), {:select_all, []})
  end

  @impl Backend
  def replace_all(entries) do
    GenServer.call(genserver_name(), {:replace_all, [entries]}, :infinity)
  end

  @impl Backend
  def delete_by_path(path) do
    GenServer.call(genserver_name(), {:delete_by_path, [path]})
  end

  @impl Backend
  def find_by_subject(subject, type, subtype) do
    GenServer.call(genserver_name(), {:find_by_subject, [subject, type, subtype]})
  end

  @impl Backend
  def find_by_ids(ids, type, subtype) do
    GenServer.call(genserver_name(), {:find_by_ids, [ids, type, subtype]})
  end

  @impl Backend
  def structure_for_path(path) do
    GenServer.call(genserver_name(), {:structure_for_path, [path]})
  end

  @impl Backend
  def siblings(%Entry{} = entry) do
    GenServer.call(genserver_name(), {:siblings, [entry]})
  end

  @impl Backend
  def parent(%Entry{} = entry) do
    GenServer.call(genserver_name(), {:parent, [entry]})
  end

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project])
  end

  @impl GenServer
  def init([%Project{} = project]) do
    :ok = connect_to_project_nodes(project)
    {:ok, project, {:continue, :try_for_leader}}
  end

  @impl GenServer
  def handle_continue(:try_for_leader, %Project{} = project) do
    leader_name = leader_name(project)

    with :undefined <- :global.whereis_name(leader_name),
         :ok <- become_leader(project) do
      {:noreply, create_leader(project)}
    else
      _ ->
        {:noreply, follow_leader(project)}
    end
  end

  @impl GenServer
  def handle_call(:prepare, _from, %State{} = state) do
    case State.prepare(state) do
      {:error, :not_leader} = error ->
        {:stop, :normal, error, state}

      {reply, new_state} ->
        {:reply, reply, new_state}
    end
  end

  def handle_call(:sync, _from, %State{} = state) do
    state = State.sync(state)
    {:reply, :ok, state}
  end

  def handle_call({function_name, arguments}, _from, %State{} = state) do
    arguments = [state | arguments]
    reply = apply(State, function_name, arguments)
    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _, _reason}, %State{leader?: true} = state) do
    # ets died, and we own it. Restart it

    {:noreply, create_leader(state.project)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{leader_pid: pid} = state) do
    {:noreply, state.project, {:continue, :try_for_leader}}
  end

  def handle_info({:global_name_conflict, {:ets_search, _}}, %State{} = state) do
    # This clause means we were randomly notified by the call to
    # :global.random_notify_name. We've been selected to be the leader!
    new_state = become_leader(state.project)
    {:noreply, new_state}
  end

  # Private

  defp leader_name(%Project{} = project) do
    {:ets_search, Project.name(project)}
  end

  defp genserver_name do
    genserver_name(RemoteControl.get_project())
  end

  defp genserver_name(%Project{} = project) do
    {:global, leader_name(project)}
  end

  defp become_leader(%Project{} = project) do
    leader_name = leader_name(project)
    :global.trans(leader_name, fn -> do_become_leader(project) end, [], 0)
  end

  defp do_become_leader(%Project{} = project) do
    leader_name = leader_name(project)

    with :undefined <- :global.whereis_name(leader_name),
         :yes <- :global.register_name(leader_name, self(), &:global.random_notify_name/3) do
      Process.flag(:trap_exit, true)
      :ok
    else
      _ ->
        :error
    end
  end

  defp follow_leader(%Project{} = project) do
    leader_pid = :global.whereis_name(leader_name(project))
    Process.monitor(leader_pid)
    State.new_follower(project, leader_pid)
  end

  defp create_leader(%Project{} = project) do
    State.new_leader(project)
  end

  defp connect_to_project_nodes(%Project{} = project) do
    case :erl_epmd.names() do
      {:ok, node_names_and_ports} ->
        project
        |> project_nodes(node_names_and_ports)
        |> Enum.each(&Node.connect/1)

        :global.sync()

      _ ->
        :ok
    end
  end

  defp project_nodes(%Project{} = project, node_and_port_list) do
    project_name = Project.name(project)

    project_substring = "project-#{project_name}-"

    for {node_name_charlist, _port} <- node_and_port_list,
        node_name_string = List.to_string(node_name_charlist),
        String.contains?(node_name_string, project_substring) do
      :"#{node_name_string}@127.0.0.1"
    end
  end
end
