defmodule Lexical.RemoteControl.Commands.Rename.StateTest do
  alias Lexical.RemoteControl.Commands.Rename.State
  use ExUnit.Case
  use Patch

  test "it should decrease the change count once marked as changed." do
    file_uri = "file://file.ex"
    initial_state = State.new(%{file_uri => 2})
    state = State.mark_changed(initial_state, file_uri)
    assert state.uri_with_operation_counts == %{file_uri => 1}
  end

  test "it should remove the uri from the state once marked as saved." do
    file_uri = "file://file.ex"
    initial_state = State.new(%{file_uri => 1})
    state = State.mark_saved(initial_state, file_uri)
    assert state.uri_with_operation_counts == %{}
  end

  test "it should not changed the `in_progress` state when the `uri` not in the state." do
    initial_state = State.new(%{})
    state = State.mark_changed(initial_state, "file://file.ex")
    refute State.in_progress?(state)
  end

  test "it should return true if there are uris with change counts." do
    initial_state = State.new(%{"file://file.ex" => 1})

    assert State.in_progress?(initial_state)
  end

  test "it should return false if there are no uris with change counts." do
    initial_state = State.new(%{})

    refute State.in_progress?(initial_state)
  end
end
