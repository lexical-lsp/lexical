defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.Project
  alias Lexical.RemoteControl
  require Logger

  defmodule State do
    defstruct [:project, :node, :paths, :cookie, :stopped_by, :stop_timeout, :status]

    def new(%Project{} = project) do
      cookie = Node.get_cookie()

      %__MODULE__{
        project: project,
        node: node_name(project),
        paths: RemoteControl.glob_paths(),
        cookie: cookie
      }
    end

    def set_stopped_by(state, from, stop_timeout) do
      %{state | stopped_by: from, stop_timeout: stop_timeout}
    end

    def stop(state) do
      %{state | status: :stopped}
    end

    def node_name(%Project{} = project) do
      :"#{Project.name(project)}@127.0.0.1"
    end
  end

  alias Lexical.RemoteControl.ProjectNodeSupervisor
  use GenServer

  def wait_until_started(project, project_listener, boot_timeout \\ 5_000) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    {:ok, node_pid} = ProjectNodeSupervisor.start_project_node(project)

    node = State.node_name(project)
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

  @stop_timeout 1_000
  def stop(project, stop_timeout \\ @stop_timeout) do
    project |> name() |> GenServer.call({:stop, stop_timeout}, stop_timeout + 500)
  end

  def child_spec(project) do
    %{
      id: name(project),
      start: {__MODULE__, :start_link, [project]},
      restart: :temporary
    }
  end

  def start_link(project) do
    state = State.new(project)
    GenServer.start_link(__MODULE__, state, name: name(project))
  end

  @impl GenServer
  def init(state) do
    {:ok, state, {:continue, :start_remote_control}}
  end

  @impl true
  def handle_continue(:start_remote_control, state) do
    {:ok, elixir_executable} = RemoteControl.elixir_executable(state.project)

    cmd =
      "#{elixir_executable} --name #{state.node} #{path_append_arguments(state)} --cookie #{state.cookie} --no-halt " <>
        "-e 'Node.connect(#{inspect(Node.self())})' "

    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    spawn(fn -> System.shell(cmd) end)
    {:noreply, state}
  end

  @impl true
  def handle_call({:stop, stop_timeout}, from, state) do
    state = State.set_stopped_by(state, from, stop_timeout)
    Process.send_after(self(), :stop_timeout, state.stop_timeout)
    :rpc.call(state.node, System, :stop, [])

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _, _}, state) do
    state = State.stop(state)

    # NOTE: when I use `RemoteControl.stop(project, 2_000)`
    GenServer.reply(state.stopped_by, :ok)
    {:stop, :shutdown, nil}
  end

  @impl true
  def handle_info(:stop_timeout, %{status: status} = state) when status != :stopped do
    Node.monitor(state.node, false)
    :rpc.call(state.node, System, :halt, [])
    state = State.stop(state)

    # NOTE: when I use `RemoteControl.stop(project, 1_000)`
    GenServer.reply(state.stopped_by, :ok)
    {:stop, :shutdown, nil}
  end

  @impl true
  def handle_info(msg, state) do
    "Received unexpected message #{inspect(msg)}"
    {:noreply, state}
  end

  defp path_append_arguments(%State{} = state) do
    Enum.map(state.paths, fn path ->
      expanded_path = Path.expand(path)
      "-pa #{expanded_path} "
    end)
    |> IO.iodata_to_binary()
  end

  def name(%Project{} = project) do
    :"#{Project.name(project)}::node_process"
  end
end
