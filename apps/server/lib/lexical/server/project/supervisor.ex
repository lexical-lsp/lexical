defmodule Lexical.Server.Project.Supervisor do
  alias Lexical.Project
  alias Lexical.RemoteControl.ProjectNodeSupervisor
  alias Lexical.Server.Project.Diagnostics
  alias Lexical.Server.Project.Intelligence
  alias Lexical.Server.Project.Node
  alias Lexical.Server.Project.Progress

  use Supervisor

  def dynamic_supervisor_name do
    Lexical.Server.ProjectSupervisor
  end

  def options do
    [name: dynamic_supervisor_name(), strategy: :one_for_one]
  end

  def start_link(%Project{} = project) do
    Supervisor.start_link(__MODULE__, project, name: supervisor_name(project))
  end

  def init(%Project{} = project) do
    children = [
      {Progress, project},
      {ProjectNodeSupervisor, project},
      {Node, project},
      {Diagnostics, project},
      {Intelligence, project}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start(%Project{} = project) do
    DynamicSupervisor.start_child(dynamic_supervisor_name(), {__MODULE__, project})
  end

  def stop(%Project{} = project) do
    pid =
      project
      |> supervisor_name()
      |> Process.whereis()

    DynamicSupervisor.terminate_child(dynamic_supervisor_name(), pid)
  end

  defp supervisor_name(%Project{} = project) do
    :"#{Project.name(project)}::supervisor"
  end
end
