defmodule Lexical.RemoteControlTest do
  alias Lexical.Project
  alias Lexical.SourceFile
  alias Lexical.RemoteControl

  use ExUnit.Case
  import Lexical.Test.Fixtures

  def start_project(%Project{} = project) do
    assert {:ok, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      RemoteControl.stop(project)
    end)

    :ok
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

      project_path = RemoteControl.call(subapp_project, File, :cwd!, [])

      Project.root_path(parent_project)

      assert project_path == Project.root_path(parent_project)
    end

    test "keeps the current directory if it's started in the parent app" do
      parent_project = project(:umbrella)
      start_project(parent_project)

      project_path = RemoteControl.call(parent_project, File, :cwd!, [])

      Project.root_path(parent_project)

      assert project_path == Project.root_path(parent_project)
    end
  end
end
