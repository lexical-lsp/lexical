defmodule Lexical.Server.CodeIntelligence.Completion.EnvTest do
  alias Lexical.Server.CodeIntelligence.Completion
  alias Lexical.SourceFile
  alias Lexical.Test.CursorSupport
  alias Lexical.Test.Fixtures

  use ExUnit.Case
  import Completion.Env
  import CursorSupport
  import Fixtures

  def new_env(text) do
    project = project()
    {line, column} = cursor_position(text)
    stripped_text = context_before_cursor(text)
    source_file = SourceFile.new("file://foo.ex", stripped_text, 0)

    position = SourceFile.Position.new(line, column)

    {:ok, env} = new(project, source_file, position)

    env
  end

  describe "struct_reference?/1" do
    test "is true if the reference starts on the beginning of the line" do
      env = new_env("%User|")
      assert struct_reference?(env)
    end

    test "is true if the reference starts in function arguments" do
      env = new_env("def my_function(%Use|)")
      assert struct_reference?(env)
    end

    test "is true if a module reference starts in function arguments" do
      env = new_env("def my_function(%__|)")
      assert struct_reference?(env)
    end

    test "is true if the reference is for %__MOD in a function definition " do
      env = new_env("def my_fn(%__MOD")
      assert struct_reference?(env)
    end

    test "is false if the reference is for %__MOC in a function definition" do
      env = new_env("def my_fn(%__MOC)")
      refute struct_reference?(env)
    end

    test "is false if a module reference lacks a %" do
      env = new_env("def my_function(__|)")
      refute struct_reference?(env)
    end

    test "is true if the reference is on the right side of a match" do
      env = new_env("foo = %Use|")
      assert struct_reference?(env)
    end

    test "is true if the reference is on the left side of a match" do
      env = new_env(" %Use| = foo")
      assert struct_reference?(env)
    end

    test "is true if the reference is for %__} " do
      env = new_env("%__")
      assert struct_reference?(env)
    end
  end

  describe "function_capture?/1" do
    test "is true if the capture starts at the beginning of the line" do
      env = new_env("&Enum")
      assert function_capture?(env)
    end

    test "is true if the capture is inside a function call" do
      env = new_env("list = Enum.map(1..10, &Enum|)")
      assert function_capture?(env)
    end

    test "is true if the capture is inside an unformatted function call" do
      env = new_env("list = Enum.map(1..10,&Enum|)")
      assert function_capture?(env)
    end

    test "is true if the capture is inside a function call after the dot" do
      env = new_env("list = Enum.map(1..10, &Enum.f|)")
      assert function_capture?(env)
    end

    test "is true if the capture is in the body of a for" do
      env = new_env("for x <- Enum.map(1..10, &String.|)")
      assert function_capture?(env)
    end

    test "is false if the capture starts at the beginning of the line" do
      env = new_env("Enum|")
      refute function_capture?(env)
    end

    test "is false if the capture is inside a function call" do
      env = new_env("list = Enum.map(1..10, Enum|)")
      refute function_capture?(env)
    end

    test "is false if the capture is inside an unformatted function call" do
      env = new_env("list = Enum.map(1..10,Enum|)")
      refute function_capture?(env)
    end

    test "is false if the capture is inside a function call after the dot" do
      env = new_env("list = Enum.map(1..10, Enum.f|)")
      refute function_capture?(env)
    end

    test "is false if the capture is in the body of a for" do
      env = new_env("for x <- Enum.map(1..10, String.|)")
      refute function_capture?(env)
    end
  end

  describe "pipe?/1" do
    test "is true if the pipe is on the start of the line" do
      env = new_env("|> foo|()")
      assert pipe?(env)
    end

    test "is true if the pipe is in a function call" do
      env = new_env("foo( a |> b |> c|)")
      assert pipe?(env)
    end

    test "is false if the pipe is in a function call and the cursor is outside it" do
      env = new_env("foo( a |> b |> c)|")
      refute pipe?(env)
    end

    test "is false if there is no pipe in the string" do
      env = new_env("Enum.|foo")
      refute pipe?(env)
    end
  end
end
