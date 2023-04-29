defmodule Lexical.RemoteControl.ProjectNodeTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ProjectNode
  alias Lexical.RemoteControl.ProjectNodeSupervisor

  import Lexical.Test.Fixtures
  use ExUnit.Case, async: false

  def with_project(project_name) do
    project_name = to_string(project_name)
    fixture_dir = Path.join(fixtures_path(), project_name)
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, project}
  end

  test "it should be able to stop a project node and won't restart" do
    {:ok, project} = with_project(:project_metadata)
    {:ok, _node_name, _} = RemoteControl.start_link(project, self())

    assert ProjectNode.name(project) |> Process.whereis() |> Process.alive?()
    assert :ok = RemoteControl.stop(project)
    assert Process.whereis(ProjectNode.name(project)) == nil
  end
end
