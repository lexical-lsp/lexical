defmodule Lexical.RemoteControl.Dispatch.PubSubStateTest do
  use ExUnit.Case

  alias Lexical.RemoteControl.Dispatch.PubSub.State

  setup do
    state = State.new()
    {:ok, state: state}
  end

  def pid do
    spawn(fn -> :ok end)
  end

  describe "add/3" do
    test "works for a specific type", %{state: state} do
      state = State.add(state, :project_compiled, self())
      assert State.registered?(state, :project_compiled, self())
      refute State.registered?(state, :other_message, self())
    end

    test "works for all messages", %{state: state} do
      state = State.add(state, :all, self())
      assert State.registered?(state, :all, self())
      assert State.registered?(state, :whatever, self())
    end
  end

  describe "remove/3" do
    test "can be removed", %{state: state} do
      state = State.add(state, :project_compiled, self())
      assert State.registered?(state, :project_compiled, self())

      state = State.remove(state, :project_compiled, self())
      refute State.registered?(state, :project_compiled, self())
    end
  end

  describe "remove_all/2" do
    test "all registrations can be removed", %{state: state} do
      state =
        state
        |> State.add(:project_compiled, self())
        |> State.add(:other_message, self())
        |> State.add(:yet_another_message, self())
        |> State.remove_all(self())

      refute State.registered?(state, :project_compiled, self())
      refute State.registered?(state, :other_message, self())
      refute State.registered?(state, :yet_another_message, self())
    end
  end

  describe "registered?/2" do
    test "returns true if a process is registered to all", %{state: state} do
      state = State.add(state, :all, self())
      assert State.registered?(state, self())
    end

    test "returns true if a process is registered to a specific message", %{state: state} do
      state = State.add(state, :project_compiled, self())
      assert State.registered?(state, self())
    end

    test "returns false if a process isn't registered", %{state: state} do
      refute State.registered?(state, self())
    end
  end

  describe "registrations/2" do
    test "can see which things are registered for a given message type", %{state: state} do
      first = pid()
      second = pid()
      third = pid()

      state =
        state
        |> State.add(:project_compiled, first)
        |> State.add(:project_compiled, second)
        |> State.add(:project_compiled, third)

      pids = State.registrations(state, :project_compiled)
      assert first in pids
      assert second in pids
      assert third in pids
    end

    test "includes those pids registered to all", %{state: state} do
      first = pid()
      second = pid()
      third = pid()

      state =
        state
        |> State.add(:project_compiled, first)
        |> State.add(:project_compiled, second)
        |> State.add(:all, third)

      pids = State.registrations(state, :project_compiled)
      assert first in pids
      assert second in pids
      assert third in pids
    end
  end
end
