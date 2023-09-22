defmodule Lexical.RemoteControl.Search.Store.Backends.Cub do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Store.Backend
  alias Lexical.RemoteControl.Search.Store.Backends.Cub.State

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
    :ok
  end

  @impl Backend
  def insert(entries) do
    GenServer.call(genserver_name(), {:insert, entries}, :infinity)
  end

  @impl Backend
  def drop do
    GenServer.call(genserver_name(), :drop)
  end

  @impl Backend

  def destroy(%Project{} = project) do
    project
    |> cub_directory()
    |> File.rm_rf()
  end

  @impl Backend
  def select_all do
    GenServer.call(genserver_name(), :select_all)
  end

  @impl Backend
  def replace_all(entries) do
    GenServer.call(genserver_name(), {:replace_all, entries}, :infinity)
  end

  @impl Backend
  def delete_by_path(path) do
    GenServer.call(genserver_name(), {:delete_by_path, path})
  end

  @impl Backend
  def find_by_subject(subject, type, subtype) do
    GenServer.call(genserver_name(), {:find_by_subject, subject, type, subtype})
  end

  @impl Backend
  def find_by_refs(references, type, subtype) do
    GenServer.call(genserver_name(), {:find_by_references, references, type, subtype})
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
         {:ok, :leader} <- :global.trans(leader_name, fn -> become_leader(project) end, [], 0) do
      Process.flag(:trap_exit, true)
      {:noreply, initialize_cub(project)}
    else
      _ ->
        leader_pid = :global.whereis_name(leader_name(project))
        Process.monitor(leader_pid)
        {:noreply, State.new_follower(project, leader_pid)}
    end
  end

  @impl GenServer
  def handle_call(:prepare, _from, %State{} = state) do
    reply = State.prepare(state)
    {:reply, reply, state}
  end

  def handle_call({:insert, entries}, _from, %State{} = state) do
    reply = State.insert(state, entries)
    {:reply, reply, state}
  end

  def handle_call({:replace_all, entries}, _from, %State{} = state) do
    reply = State.replace_all(state, entries)
    {:reply, reply, state}
  end

  def handle_call(:select_all, _from, %State{} = state) do
    reply = State.select_all(state)
    {:reply, reply, state}
  end

  def handle_call({:find_by_references, references, type, subtype}, _from, %State{} = state) do
    reply = State.find_by_references(state, type, subtype, references)
    {:reply, reply, state}
  end

  def handle_call({:find_by_subject, subject, type, subtype}, _from, %State{} = state) do
    reply = State.find_by_subject(state, type, subtype, subject)
    {:reply, reply, state}
  end

  def handle_call({:delete_by_path, path}, _from, %State{} = state) do
    reply = State.delete_by_path(state, path)
    {:reply, reply, state}
  end

  def handle_call(:drop, _from, %State{} = state) do
    reply = State.drop(state)
    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _, _reason}, %State{leader?: true} = state) do
    # cub died, and we own it. Restart it

    {:noreply, initialize_cub(state.project)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{leader_pid: pid} = state) do
    {:noreply, state.project, {:continue, :try_for_leader}}
  end

  def handle_info({:global_name_conflict, {:cub, _}}, %State{} = state) do
    # This clause means we were randomly notified by the call to
    # :global.random_notify_name. We've been selected to be the leader!
    new_state = become_leader(state.project)
    {:noreply, new_state}
  end

  # Private

  defp leader_name(%Project{} = project) do
    {:cub, Project.name(project)}
  end

  defp genserver_name do
    genserver_name(RemoteControl.get_project())
  end

  defp genserver_name(%Project{} = project) do
    {:global, leader_name(project)}
  end

  defp become_leader(%Project{} = project) do
    case :global.register_name(leader_name(project), self(), &:global.random_notify_name/3) do
      :yes ->
        {:ok, :leader}

      :no ->
        :aborted
    end
  end

  defp initialize_cub(%Project{} = project) do
    with {:ok, cub_pid} <- CubDB.start_link(cub_directory(project), auto_compact: true) do
      State.new_leader(project, cub_pid)
    end
  end

  defp cub_directory(%Project{} = project) do
    Project.workspace_path(project, Path.join("indexes", "cubdb"))
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
