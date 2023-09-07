defmodule Lexical.Server.Project.Node do
  @moduledoc """
  A genserver responsibile for starting the remote node and cleaning up the build directory if it crashes
  """

  defmodule State do
    defstruct [:project, :node, :supervisor_pid]

    def new(project, node, supervisor_pid) do
      %__MODULE__{project: project, node: node, supervisor_pid: supervisor_pid}
    end
  end

  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.Server.Project.Progress

  require Logger

  use GenServer
  use Progress.Support

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, project, name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  def name(%Project{} = project) do
    :"#{Project.name(project)}::node"
  end

  def node_name(%Project{} = project) do
    project
    |> name()
    |> GenServer.call(:node_name)
  end

  def trigger_build(%Project{} = project) do
    project
    |> name()
    |> GenServer.cast(:trigger_build)
  end

  @impl GenServer
  def init(%Project{} = project) do
    case start_node(project) do
      {:ok, state} ->
        {:ok, state, {:continue, :trigger_build}}

      error ->
        {:stop, error}
    end
  end

  @impl GenServer
  def handle_continue(:trigger_build, %State{} = state) do
    RemoteControl.Api.schedule_compile(state.project, true)
    {:noreply, state}
  end

  @impl true
  def handle_call(:node_name, _from, %State{} = state) do
    {:reply, state.node, state}
  end

  @impl GenServer
  def handle_cast(:trigger_build, %State{} = state) do
    RemoteControl.Api.schedule_compile(state.project, true)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodedown, _}, %State{} = state) do
    Logger.warning("The node has died. Restarting after deleting the build directory")

    with :ok <- delete_build_artifacts(state.project),
         {:ok, new_state} <- start_node(state.project) do
      {:noreply, new_state}
    else
      error ->
        {:stop, error, state}
    end
  end

  # private api

  def start_node(%Project{} = project) do
    with {:ok, node, node_pid} <- RemoteControl.start_link(project) do
      Node.monitor(node, true)
      {:ok, State.new(project, node, node_pid)}
    end
  end

  defp delete_build_artifacts(%Project{} = project) do
    case File.rm_rf(Project.build_path(project)) do
      {:ok, _deleted} -> :ok
      error -> error
    end
  end
end
