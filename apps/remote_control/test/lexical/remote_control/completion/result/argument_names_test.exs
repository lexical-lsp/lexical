defmodule Lexical.RemoteControl.Completion.Result.ArgumentNamesTest do
  alias Lexical.RemoteControl.Completion.Result.ArgumentNames

  use ExUnit.Case
  import ArgumentNames

  describe "parsing elixir sense argument names" do
    test "handles normal arguments" do
      assert ~w(first second third) == from_elixir_sense(~w(first second third), 3)
    end

    test "handles default arguments in the first position" do
      args = ["first \\\\ 3", "second", "third"]

      assert ~w(second third) == from_elixir_sense(args, 2)
      assert ~w(first second third) == from_elixir_sense(args, 3)
    end

    test "handles default arguments in the middle" do
      args = ["first", "second \\\\", "third"]

      assert ~w(first third) = from_elixir_sense(args, 2)
      assert ~w(first second third) = from_elixir_sense(args, 3)
    end

    test "handles default arguments at the last position" do
      args = ["first", "second", "third \\\\ 3"]

      assert ~w(first second) = from_elixir_sense(args, 2)
      assert ~w(first second third) = from_elixir_sense(args, 3)
    end

    test "handles multiple default arguments" do
      args = ["first", "second \\\\ 1", "third", "fourth \\\\ 2", "fifth \\\\ 3", "sixth"]

      assert ~w(first third sixth) = from_elixir_sense(args, 3)
      assert ~w(first second third sixth) = from_elixir_sense(args, 4)
      assert ~w(first second third fourth sixth) = from_elixir_sense(args, 5)
      assert ~w(first second third fourth fifth sixth) = from_elixir_sense(args, 6)
    end

    test "handles struct defaults" do
      args = ["first", "second \\\\ %Struct{}", "third"]

      assert ~w(first third) = from_elixir_sense(args, 2)
      assert ~w(first second third) = from_elixir_sense(args, 3)
    end

    test "handles incorrect arity" do
      args = ~w(first second third)
      assert :error == from_elixir_sense(args, 1)
      assert :error == from_elixir_sense(args, 2)
      assert :error == from_elixir_sense(args, 4)
    end
  end
end
