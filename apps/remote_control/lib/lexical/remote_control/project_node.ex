defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.Project
  alias Lexical.RemoteControl
  require Logger

  defmodule State do
    defstruct [
      :project,
      :node,
      :paths,
      :cookie,
      :stopped_by,
      :stop_timeout,
      :started_by,
      :status
    ]

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

    def set_started_by(state, from) do
      %{state | started_by: from}
    end

    def set_started(state) do
      %{state | status: :started}
    end

    def node_name(%Project{} = project) do
      :"#{Project.name(project)}@127.0.0.1"
    end
  end

  alias Lexical.RemoteControl.ProjectNodeSupervisor
  use GenServer

  def start(project, project_listener) do
    node = State.node_name(project)
    remote_control_config = Application.get_all_env(:remote_control)

    {:ok, node_pid} = ProjectNodeSupervisor.start_project_node(project)

    with :ok <- start_node(project),
         :ok <-
           :rpc.call(node, RemoteControl.Bootstrap, :init, [
             project,
             project_listener,
             remote_control_config
           ]) do
      {:ok, node_pid}
    end
  end

  @start_timeout 5_000

  defp start_node(project) do
    project |> name() |> GenServer.call(:start, @start_timeout + 500)
  end

  @stop_timeout 1_000

  def stop(project, stop_timeout \\ @stop_timeout) do
    project |> name() |> GenServer.call({:stop, stop_timeout}, stop_timeout + 100)
  end

  def child_spec(project) do
    %{
      id: name(project),
      start: {__MODULE__, :start_link, [project]},
      restart: :transient
    }
  end

  def start_link(project) do
    state = State.new(project)
    GenServer.start_link(__MODULE__, state, name: name(project))
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:start, from, state) do
    port_wrapper = port_wrapper_executable()
    {:ok, elixir_executable} = RemoteControl.elixir_executable(state.project)

    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    Process.send_after(self(), :maybe_start_timeout, @start_timeout)

    _port =
      Port.open({:spawn_executable, port_wrapper},
        args:
          [
            elixir_executable,
            "--name",
            state.node,
            "--cookie",
            state.cookie,
            "--no-halt",
            "-e",
            "Node.connect(#{inspect(Node.self())})"
          ] ++ path_append_arguments(state)
      )

    state = State.set_started_by(state, from)
    {:noreply, state}
  end

  @impl true
  def handle_call({:stop, stop_timeout}, from, state) do
    state = State.set_stopped_by(state, from, stop_timeout)
    :rpc.call(state.node, System, :stop, [])
    {:noreply, state, stop_timeout}
  end

  @impl true
  def handle_info({:nodeup, _node, _}, state) do
    GenServer.reply(state.started_by, :ok)
    {:noreply, State.set_started(state)}
  end

  @impl true
  def handle_info(:maybe_start_timeout, %{status: status} = state) when status != :started do
    GenServer.reply(state.started_by, {:error, :start_timeout})
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(:maybe_start_timeout, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, _, _}, state) do
    GenServer.reply(state.stopped_by, :ok)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    :rpc.call(state.node, System, :halt, [])
    GenServer.reply(state.stopped_by, :ok)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({_port, {:data, message}}, state) do
    Logger.info("Port: message is is_exception: #{is_exception(message)} or #{is_map(message)}")
    message = message |> IO.iodata_to_binary() |> String.trim()
    Logger.info("Port: #{message}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warn("Received unexpected message #{inspect(msg)}")
    {:noreply, state}
  end

  defp path_append_arguments(%State{} = state) do
    Enum.map(state.paths, fn path ->
      expanded_path = Path.expand(path)
      ["-pa", "#{expanded_path}"]
    end)
    |> List.flatten()
  end

  def name(%Project{} = project) do
    :"#{Project.name(project)}::node_process"
  end

  defp port_wrapper_executable do
    Path.join(:code.priv_dir(:remote_control), "port_wrapper.sh")
  end
end
