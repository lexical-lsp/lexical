defmodule Lexical.Server.Project.Progress.StateTest do
  alias Lexical.RemoteControl
  alias Lexical.Server.Project.Progress.State
  alias Lexical.Server.Project.Progress.ProgressValue

  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  def with_a_project(_) do
    project = project()
    {:ok, %{project: project}}
  end

  test "it should be able to add a begin event and put the new token" do
    state = State.new(:project) |> State.add("deps.get.begin")

    assert %ProgressValue{
             title: "mix deps.get",
             message: nil
           } = state.progress

    assert state.token_by_label["deps.get"] != nil
  end

  describe "add `report` kind progress message" do
    setup :with_a_project

    test "it should be able to add a report event and generate percentage", %{project: project} do
      # patch(RemoteControl.Api, :all_ex_files, fn _ -> all_files end)
      state =
        State.new(project)
        |> State.add("compile.prepare", 3)
        |> State.add("compile.begin")

      %{progress: progress} = State.add(state, "compile", "lib/my_module.ex")

      assert progress.message == "lib/my_module.ex"
      assert progress.percentage == 33
    end

    test "it should be able to add a report event without percentage", %{project: project} do
      state = State.new(project) |> State.add("deps.compile.begin")

      %{progress: progress} = State.add(state, "deps.compile", "jason/lib/mix.exs")

      assert progress.message == "jason/lib/mix.exs"
      assert progress.percentage == nil
    end
  end
end
