defmodule Lexical.RemoteControl.ProjectNode do
  alias Lexical.Project
  alias Lexical.RemoteControl
  require Logger

  defmodule State do
    defstruct [
      :project,
      :port,
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
        cookie: cookie,
        status: :initializing
      }
    end

    @dialyzer {:nowarn_function, start: 3}

    def start(%__MODULE__{} = state, paths, from) do
      port_wrapper = port_wrapper_executable()
      {:ok, elixir_executable} = RemoteControl.elixir_executable(state.project)
      node_name = node_name(state.project)

      args = [
        elixir_executable,
        "--name",
        node_name,
        "--cookie",
        state.cookie,
        "--no-halt",
        "-e",
        "Node.connect(#{inspect(Node.self())})"
        | path_append_arguments(paths)
      ]

      port =
        Port.open({:spawn_executable, port_wrapper},
          args: args,
          cd: Project.root_path(state.project)
        )

      %{state | port: port, started_by: from}
    end

    def stop(%__MODULE__{} = state, from, stop_timeout) do
      :rpc.call(node_name(state.project), System, :stop, [])
      %{state | stopped_by: from, stop_timeout: stop_timeout, status: :stopping}
    end

    def halt(%__MODULE__{} = state) do
      :rpc.call(node_name(state.project), System, :halt, [])
      %{state | status: :stopped}
    end

    def on_nodeup(%__MODULE__{} = state) do
      %{state | status: :started}
    end

    def on_nodedown(%__MODULE__{} = state) do
      %{state | status: :stopped}
    end

    def on_monitored_dead(%__MODULE__{} = state) do
      if :rpc.call(node_name(state.project), Node, :alive?, []) do
        halt(state)
      else
        %{state | status: :stopped}
      end
    end

    def node_name(%Project{} = project) do
      :"#{Project.name(project)}@127.0.0.1"
    end

    defp path_append_arguments(paths) do
      Enum.flat_map(paths, fn path ->
        ["-pa", Path.expand(path)]
      end)
    end

    defp port_wrapper_executable do
      "remote_control"
      |> String.to_atom()
      |> :code.priv_dir()
      |> Path.join("port_wrapper.sh")
    end
  end

  alias Lexical.RemoteControl.ProjectNodeSupervisor
  use GenServer

  def start(project, project_listener, paths) do
    node_name = State.node_name(project)
    remote_control_config = Application.get_all_env(:remote_control)

    with {:ok, node_pid} <- ProjectNodeSupervisor.start_project_node(project),
         :ok <- start_node(project, paths),
         :ok <-
           :rpc.call(node_name, RemoteControl.Bootstrap, :init, [
             project,
             project_listener,
             remote_control_config
           ]) do
      {:ok, node_pid}
    end
  end

  @stop_timeout 1_000

  def stop(%Project{} = project, stop_timeout \\ @stop_timeout) do
    project |> name() |> GenServer.call({:stop, stop_timeout}, stop_timeout + 100)
  end

  def child_spec(%Project{} = project) do
    %{
      id: name(project),
      start: {__MODULE__, :start_link, [project]},
      restart: :transient
    }
  end

  def start_link(%Project{} = project) do
    state = State.new(project)
    GenServer.start_link(__MODULE__, state, name: name(project))
  end

  @start_timeout 3_000

  defp start_node(project, paths) do
    project |> name() |> GenServer.call({:start, paths}, @start_timeout + 500)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  def handle_call({:start, paths}, from, %State{} = state) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :visible)
    Process.send_after(self(), :maybe_start_timeout, @start_timeout)
    state = State.start(state, paths, from)
    {:noreply, state}
  end

  @impl true
  def handle_call({:stop, stop_timeout}, from, %State{} = state) do
    state = State.stop(state, from, stop_timeout)
    {:noreply, state, stop_timeout}
  end

  @impl true
  def handle_info({:nodeup, _node, _}, %State{} = state) do
    {pid, _ref} = state.started_by
    Process.monitor(pid)
    GenServer.reply(state.started_by, :ok)
    state = State.on_nodeup(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:maybe_start_timeout, %State{status: :started} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:maybe_start_timeout, %State{} = state) do
    GenServer.reply(state.started_by, {:error, :start_timeout})
    {:stop, :start_timeout, nil}
  end

  @impl true
  def handle_info({:nodedown, _, _}, %State{} = state) do
    GenServer.reply(state.stopped_by, :ok)
    state = State.on_nodedown(state)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _object, _reason}, %State{} = state) do
    state = State.on_monitored_dead(state)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %State{port: port} = state) do
    Logger.info("Port #{inspect(port)} has exited due to: #{inspect(reason)}")
    {:noreply, %State{state | port: nil}}
  end

  @impl true
  def handle_info(:timeout, %State{} = state) do
    state = State.halt(state)
    GenServer.reply(state.stopped_by, :ok)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({_port, {:data, message}}, %State{} = state) do
    Logger.warning("Port: #{inspect(IO.iodata_to_binary(message))}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, %State{} = state) do
    Logger.warning("Received unexpected message #{inspect(msg)}")
    {:noreply, state}
  end

  def name(%Project{} = project) do
    :"#{Project.name(project)}::node_process"
  end
end
