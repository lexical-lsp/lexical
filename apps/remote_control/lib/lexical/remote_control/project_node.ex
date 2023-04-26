defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.RemoteControl
  alias Lexical.Project
  require Logger

  defmodule State do
    defstruct [:project, :paths, :cookie]

    def new(%Project{} = project) do
      cookie = Node.get_cookie()
      %__MODULE__{project: project, paths: RemoteControl.glob_paths(), cookie: cookie}
    end
  end

  alias Lexical.RemoteControl.ProjectNodeSupervisor
  use GenServer

  def wait_until_started(project, project_listener, boot_timeout \\ 5_000) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    {:ok, node_pid} = ProjectNodeSupervisor.start_project_node(project)

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
      "#{elixir_executable} --name #{name} #{path_append_arguments(state)} --cookie #{state.cookie} --no-halt " <>
        "-e 'Node.connect(#{inspect(Node.self())})' "

    case System.shell(cmd) do
      {_, 0} ->
        {:noreply, state}

      _ ->
        {:stop, :boot_failed, state}
    end
  end

  def path_append_arguments(%State{} = state) do
    Enum.map(state.paths, fn path ->
      expanded_path = Path.expand(path)
      "-pa #{expanded_path} "
    end)
    |> IO.iodata_to_binary()
  end
end
