defmodule Lexical.RemoteControl.Build.ProgressTest do
  alias Lexical.RemoteControl.Build.Progress.State
  alias Lexical.RemoteControl.Build.Progress.ProgressValue

  use ExUnit.Case, async: false

  test "it should be able to add a begin event" do
    state = State.new() |> State.add("deps.get.begin")

    assert %ProgressValue{
             kind: "begin",
             title: "mix deps.get",
             message: ""
           } = state.progress
  end

  test "it should be able to add a report event and use the previous token" do
    state = State.new() |> State.add("deps.compile.begin")
    token = state.progress.token

    assert %{progress: %{token: ^token} = progress} =
             state |> State.add("deps.compile", "1/10 jason")

    assert progress.kind == "report"
    assert progress.title == "mix deps.compile"
    assert progress.message == "1/10 jason"
  end
end
