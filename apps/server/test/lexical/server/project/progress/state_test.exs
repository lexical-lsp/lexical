defmodule Lexical.Server.Project.Progress.StateTest do
  alias Lexical.Server.Project.Progress.State
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  def with_a_project(_) do
    project = project()
    {:ok, %{project: project}}
  end

  setup :with_a_project
  setup do: patch(Transport, :write, :ok)

  def message(label, message \\ nil) do
    project_progress(label: label, message: message)
  end

  test "it should be able to add a begin event and put the new token", %{project: project} do
    label = "mix deps.get"
    state = State.new(project) |> State.begin(message(label))

    assert %Value{token: token, title: ^label, kind: :begin} = state.progress_by_label[label]
    assert token != nil
  end

  test "it should be able to add a report event use the begin event token", %{project: project} do
    label = "mix compile"
    state = State.new(project) |> State.begin(message(label))

    previous_token = state.progress_by_label[label].token

    %{progress_by_label: progress_by_label} =
      State.report(state, message(label, "lib/my_module.ex"))

    assert %Value{token: ^previous_token, message: "lib/my_module.ex", kind: :report} =
             progress_by_label[label]
  end

  test "clear the token_by_label after received a complete event", %{project: project} do
    state = State.new(project) |> State.begin(message("mix compile"))

    %{progress_by_label: progress_by_label} =
      State.complete(state, message("mix compile", "in 2s"))

    assert progress_by_label == %{}
  end
end
