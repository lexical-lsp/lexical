defmodule Lexical.Server.CodeIntelligence.Completion.EnvTest do
  alias Lexical.Document
  alias Lexical.Server.CodeIntelligence.Completion
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
    document = Document.new("file://foo.ex", stripped_text, 0)

    position = Document.Position.new(line, column)

    {:ok, env} = new(project, document, position)
    env
  end

  describe "last_word/1" do
    test "is the module name" do
      env = new_env("Mod|")

      assert last_word(env) == "Mod"
    end

    test "is do if a block has been declared" do
      env = new_env("whatever do|\nend")
      assert last_word(env) == "do"
    end

    test "is a function name" do
      env = new_env("fun|")
      assert last_word(env) == "fun"
    end
  end

  describe "last_token/1" do
    test "is the module name" do
      env = new_env("Mod|")

      assert last_token(env) == "Mod"
    end

    test "works with a list literal" do
      env = new_env("[1, 2, 3, 4]")
      assert last_token(env) == "]"
    end

    test "is the name of the function after a dot" do
      env = new_env("Mod.fun|")
      assert last_token(env) == "fun"
    end

    test "is do if a block has been declared" do
      env = new_env("whatever do|\nend")
      assert last_token(env) == "do"
    end

    test "is a function name" do
      env = new_env("fun|")
      assert last_token(env) == "fun"
    end

    test "works with multiple tokens" do
      env = new_env("foo = Module.fun")
      assert last_token(env) == "fun"
    end
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
