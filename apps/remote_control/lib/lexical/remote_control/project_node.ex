defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.RemoteControl
  require Logger

  defmodule State do
    defstruct [:project, :paths, :cookie]

    def new(project) do
      paths = format_prepending_paths(RemoteControl.glob_paths())
      cookie = Node.get_cookie()

      struct!(__MODULE__, paths: paths, cookie: cookie, project: project)
    end

    defp format_prepending_paths(paths_as_charlists) do
      Enum.map_join(paths_as_charlists, " -pa ", &Path.expand/1)
    end
  end

  alias Lexical.RemoteControl.ProjectNodeSupervisor

  use GenServer

  def wait_until_started(project, project_listener, boot_timeout \\ 5_000) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)

    {:ok, node_pid} =
      DynamicSupervisor.start_child(
        ProjectNodeSupervisor,
        {RemoteControl.ProjectNode, project}
      )

    node = RemoteControl.node_name(project)
    remote_control_config = Application.get_all_env(:remote_control)

    with :ok <- wait_until(boot_timeout),
         :ok <-
           :rpc.call(node, RemoteControl.Bootstrap, :init, [
             project,
             project_listener,
             remote_control_config
           ]) do
      {:ok, node_pid}
    end
  end

  defp wait_until(timeout) do
    receive do
      {:nodeup, _, _} ->
        :ok
    after
      timeout ->
        Logger.warn("The project node did not start after #{timeout / 1000} seconds")
        {:error, :boot_timeout}
    end
  end

  def start_link(project) do
    state = State.new(project)
    GenServer.start_link(__MODULE__, state, [])
  end

  def init(state) do
    {:ok, state, {:continue, :start_remote_control}}
  end

  def handle_continue(:start_remote_control, state) do
    name = RemoteControl.node_name(state.project)
    {:ok, elixir_executable} = RemoteControl.elixir_executable(state.project)

    cmd =
      "#{elixir_executable} --name #{name} -pa #{state.paths} --cookie #{state.cookie} --no-halt " <>
        "-e 'Node.connect(#{inspect(Node.self())})' "

    case System.shell(cmd) do
      {_, 0} ->
        {:noreply, state}

      _ ->
        {:stop, :boot_failed, state}
    end
  end
end