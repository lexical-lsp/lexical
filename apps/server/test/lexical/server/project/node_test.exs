defmodule Lexical.Server.Project.NodeTest do
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Project.Node, as: ProjectNode
  alias Lexical.Server.Transport

  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch
  use Testing.EventualAssertions

  setup do
    project = project()

    patch(Transport, :write, :ok)

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})
    :ok = Server.Project.Dispatch.register(project, [project_compiled()])

    {:ok, project: project}
  end

  test "the project should be compiled when the node starts" do
    assert_receive project_compiled(), 750
  end

  test "remote control is started when the node starts", %{project: project} do
    apps = RemoteControl.call(project, Application, :started_applications)
    app_names = Enum.map(apps, &elem(&1, 0))
    assert :remote_control in app_names
  end

  test "the node is restarted when it goes down", %{project: project} do
    node_name = ProjectNode.node_name(project)
    old_pid = node_pid(project)

    :ok = RemoteControl.stop(project)
    assert_eventually Node.ping(node_name) == :pong, 1000

    new_pid = node_pid(project)
    assert is_pid(new_pid)
    assert new_pid != old_pid
  end

  test "the node restarts when the supervisor pid is killed", %{project: project} do
    node_name = ProjectNode.node_name(project)
    supervisor_pid = RemoteControl.call(project, Process, :whereis, [RemoteControl.Supervisor])

    assert is_pid(supervisor_pid)
    Process.exit(supervisor_pid, :kill)
    assert_eventually Node.ping(node_name) == :pong, 750
  end

  defp node_pid(project) do
    RemoteControl.ProjectNode.name(project) |> Process.whereis()
  end
end
