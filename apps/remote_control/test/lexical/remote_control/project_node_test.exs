defmodule Lexical.RemoteControl.ProjectNodeTest do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ProjectNode
  alias Lexical.RemoteControl.ProjectNodeSupervisor

  import Lexical.Test.Fixtures
  import Testing.EventualAssertions

  use ExUnit.Case, async: false

  setup do
    project = project()
    start_supervised!({ProjectNodeSupervisor, project})
    {:ok, %{project: project}}
  end

  test "it should be able to stop a project node and won't restart", %{project: project} do
    {:ok, _node_name, _} = RemoteControl.start_link(project, self())

    assert ProjectNode.name(project) |> Process.whereis() |> Process.alive?()
    assert :ok = ProjectNode.stop(project, 500)
    assert Process.whereis(ProjectNode.name(project)) == nil
  end

  test "it should be stopped atomically when the startup process is dead", %{project: project} do
    test_pid = self()

    linked_node_process =
      spawn(fn ->
        {:ok, _node_name, _} = RemoteControl.start_link(project, test_pid)
        send(test_pid, :started)
      end)

    assert_receive :started, 1500

    node_process_name = ProjectNode.name(project)

    assert node_process_name |> Process.whereis() |> Process.alive?()
    Process.exit(linked_node_process, :kill)
    assert_eventually Process.whereis(node_process_name) == nil, 50
  end
end
