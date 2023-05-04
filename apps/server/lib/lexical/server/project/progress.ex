defmodule Lexical.Server.Project.Progress do
  alias Lexical.Project
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Project.Progress.State
  require Logger

  import Lexical.RemoteControl.Api.Messages

  use GenServer

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  # GenServer callbacks

  @impl GenServer
  def init([project]) do
    Dispatch.register(project, [project_progress()])
    {:ok, State.new(project)}
  end

  @impl true
  def handle_info(project_progress(label: label, message: message), %State{} = state) do
    new_state =
      case State.kind(label) do
        :begin ->
          State.begin(state, label)

        :report ->
          State.update(state, label, message)

        :end ->
          State.complete(state, label, message)

        _ ->
          state
      end

    {:noreply, new_state}
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::progress"
  end
end
