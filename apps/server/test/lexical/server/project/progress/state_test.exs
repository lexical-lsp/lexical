defmodule Lexical.Server.Project.Progress.StateTest do
  alias Lexical.Server.Project.Progress.State
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  setup do
    project = project()
    patch(Transport, :write, :ok)
    {:ok, project: project}
  end

  def progress(label, message \\ nil) do
    project_progress(label: label, message: message)
  end

  test "it should be able to add a begin event and put the new token", %{project: project} do
    label = "mix deps.get"
    state = project |> State.new() |> State.begin(progress(label))

    assert %Value{token: token, title: ^label, kind: :begin} = state.progress_by_label[label]
    assert token != nil
  end

  test "it should be able to add a report event use the begin event token", %{project: project} do
    label = "mix compile"
    state = project |> State.new() |> State.begin(progress(label))

    previous_token = state.progress_by_label[label].token

    %{progress_by_label: progress_by_label} =
      State.report(state, progress(label, "lib/my_module.ex"))

    assert %Value{token: ^previous_token, message: "lib/my_module.ex", kind: :report} =
             progress_by_label[label]
  end

  test "clear the token_by_label after received a complete event", %{project: project} do
    state = project |> State.new() |> State.begin(progress("mix compile"))

    %{progress_by_label: progress_by_label} =
      State.complete(state, progress("mix compile", "in 2s"))

    assert progress_by_label == %{}
  end

  test "set the progress value to nil when there is no begin event", %{
    project: project
  } do
    state = project |> State.new() |> State.report(progress("mix compile"))
    assert state.progress_by_label["mix compile"] == nil
  end

  test "set the progress value to nil when a complete event received before the report", %{
    project: project
  } do
    label = "mix compile"

    state =
      project
      |> State.new()
      |> State.begin(progress(label))
      |> State.complete(progress(label, "in 2s"))

    %{progress_by_label: progress_by_label} =
      State.report(state, progress(label, "lib/my_module.ex"))

    assert progress_by_label[label] == nil
  end
end
