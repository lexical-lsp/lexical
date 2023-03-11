defmodule Lexical.Server.CodeIntelligence.Completion.EnvTest do
  alias Lexical.Server.CodeIntelligence.Completion
  alias Lexical.Protocol.Types.Completion.Context
  alias Lexical.SourceFile
  alias Lexical.Test.Fixtures
  alias Lexical.Test.CursorSupport

  use ExUnit.Case
  import Fixtures
  import CursorSupport

  def new_env(text) do
    project = project()
    stripped_text = String.replace(text, "|", "")
    source_file = SourceFile.new("file://foo.ex", stripped_text, 0)
    {line, column} = cursor_position(text)
    position = SourceFile.Position.new(line, column)

    {:ok, env} =
      Completion.Env.new(project, source_file, position, Context.new(trigger_kind: :invoked))

    env
  end

  describe "struct_reference?/1" do
    test "is true if the reference starts on the beginning of the line" do
      env = new_env("%User|")
      assert Completion.Env.struct_reference?(env)
    end

    test "is true if the reference starts in function arguments" do
      env = new_env("def my_function(%Use|)")
      assert Completion.Env.struct_reference?(env)
    end

    test "is true if a module reference starts in function arguments" do
      env = new_env("def my_function(%__|)")
      assert Completion.Env.struct_reference?(env)
    end

    test "is false if a module reference lacks a %" do
      env = new_env("def my_function(__|)")
      refute Completion.Env.struct_reference?(env)
    end

    test "is true if the reference is on the right side of a match" do
      env = new_env("foo = %Use|")
      assert Completion.Env.struct_reference?(env)
    end

    test "is true if the reference is on the left side of a match" do
      env = new_env(" %Use| = foo")
      assert Completion.Env.struct_reference?(env)
    end

    test "is true if the reference is for %__} " do
      env = new_env("%__")
      assert Completion.Env.struct_reference?(env)
    end
  end
end
