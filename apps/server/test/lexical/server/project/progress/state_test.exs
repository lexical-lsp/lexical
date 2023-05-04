defmodule Lexical.Server.Project.Progress.StateTest do
  alias Lexical.Server.Project.Progress.State
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  def with_a_project(_) do
    project = project()
    {:ok, %{project: project}}
  end

  setup :with_a_project
  setup do: patch(Transport, :write, :ok)

  test "it should be able to add a begin event and put the new token", %{project: project} do
    state = State.new(project) |> State.begin("mix deps.get.begin")

    assert %Value{token: token, title: "mix deps.get", kind: :begin} = state.progress
    assert token != nil
    assert state.token_by_label["mix deps.get"] == token
  end

  test "it should be able to add a report event use the begin event token", %{project: project} do
    %{progress: %{token: token}} = state = State.new(project) |> State.begin("mix compile.begin")

    %{progress: progress} = State.update(state, "mix compile", "lib/my_module.ex")

    assert %Value{token: ^token, message: "lib/my_module.ex", kind: :report} = progress
  end

  test "clear the token_by_label after received a complete event", %{project: project} do
    state = State.new(project) |> State.begin("mix compile.begin")

    state = State.complete(state, "mix compile.end", "lib/my_module.ex")

    assert state.token_by_label == %{}
  end
end
