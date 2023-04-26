defmodule Lexical.RemoteControlTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.SourceFile

  use ExUnit.Case
  use Testing.EventualAssertions
  import Lexical.Test.Fixtures

  def start_project(%Project{} = project) do
    start_supervised!({Lexical.RemoteControl.ProjectNodeSupervisor, project})
    assert {:ok, _, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      RemoteControl.stop(project)
    end)

    :ok
  end

  def remote_control_cwd(project) do
    RemoteControl.call(project, File, :cwd!, [])
  end

  describe "detecting an umbrella app" do
    test "it changes the directory to the root if it's started in a subapp" do
      parent_project = project(:umbrella)

      subapp_project =
        [fixtures_path(), "umbrella", "apps", "first"]
        |> Path.join()
        |> SourceFile.Path.to_uri()
        |> Project.new()

      start_project(subapp_project)

      assert_eventually remote_control_cwd(subapp_project) == Project.root_path(parent_project),
                        250
    end

    test "keeps the current directory if it's started in the parent app" do
      parent_project = project(:umbrella)
      start_project(parent_project)

      assert_eventually remote_control_cwd(parent_project) == Project.root_path(parent_project),
                        250
    end
  end
end
