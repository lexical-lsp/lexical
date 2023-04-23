defmodule Lexical.Server.Project.NodeTest do
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Project.Node, as: ProjectNode

  use ExUnit.Case
  use Testing.EventualAssertions

  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  setup do
    project = project()

    {:ok, _} = start_supervised(Lexical.RemoteControl.ProjectNodeSupervisor)

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})
    :ok = Server.Project.Dispatch.register(project, [project_compiled()])

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

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
    assert :pong = Node.ping(node_name)
    :ok = RemoteControl.stop(project)

    assert_eventually Node.ping(node_name) == :pong, 750
  end

  test "the node restarts when the supervisor pid is killed", %{project: project} do
    node_name = ProjectNode.node_name(project)
    supervisor_pid = RemoteControl.call(project, Process, :whereis, [RemoteControl.Supervisor])

    assert is_pid(supervisor_pid)
    Process.exit(supervisor_pid, :kill)
    assert_eventually Node.ping(node_name) == :pong, 750
  end
end
