defmodule Lexical.RemoteControl.ProgressTest do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Progress

  import Lexical.RemoteControl.Api.Messages

  use ExUnit.Case
  use Patch
  use Progress

  setup do
    test_pid = self()
    patch(RemoteControl.Dispatch, :broadcast, &send(test_pid, &1))
    :ok
  end

  test "it should send begin/complete event and return the result" do
    result = with_progress "foo", fn -> :ok end

    assert result == :ok
    assert_received project_progress(label: "foo", stage: :begin)
    assert_received project_progress(label: "foo", stage: :complete)
  end

  test "it should send begin/complete event even there is an exception" do
    assert_raise(Mix.Error, fn ->
      with_progress "compile", fn -> raise Mix.Error, "can't compile" end
    end)

    assert_received project_progress(label: "compile", stage: :begin)
    assert_received project_progress(label: "compile", stage: :complete)
  end
end
