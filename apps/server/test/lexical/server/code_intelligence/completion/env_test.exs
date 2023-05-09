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

  describe "prefix_tokens/2" do
    test "works with bitstring specifiers" do
      env = new_env("<<foo::int|")
      assert [{:identifier, 'int'}, {:operator, :"::"}] = prefix_tokens(env, 2)
    end

    test "works with floats" do
      tokens =
        "27.88"
        |> new_env()
        |> prefix_tokens(1)

      assert [{:float, 27.88}] = tokens
    end

    test "works with strings" do
      tokens =
        ~s("hello")
        |> new_env()
        |> prefix_tokens(1)

      assert [{:string, "hello"}] = tokens
    end

    test "works with maps with atom keys" do
      tokens =
        "%{a: 3}"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:curly, :"}"},
               {:int, 3},
               {:kw_identifier, 'a'},
               {:curly, :"{"},
               {:map_new, :%{}}
             ] = tokens
    end

    test "works with maps with string keys" do
      tokens =
        ~s(%{"a" => 3})
        |> new_env()
        |> prefix_tokens(8)

      assert [
               {:curly, :"}"},
               {:int, 3},
               {:assoc_op, nil},
               {:string, "a"},
               {:curly, :"{"},
               {:map_new, :%{}}
             ] = tokens
    end

    test "works with pattern matches" do
      tokens =
        "my_var = 3 + 5"
        |> new_env()
        |> prefix_tokens(3)

      assert tokens == [
               {:int, 5},
               {:operator, :+},
               {:int, 3}
             ]
    end

    test "works with remote function calls" do
      tokens =
        "Enum.map|"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:identifier, 'map'},
               {:operator, :.},
               {:alias, 'Enum'}
             ] = tokens
    end

    test "works with local function calls" do
      tokens =
        "foo = local(|"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:paren, :"("},
               {:paren_identifier, 'local'},
               {:match_op, nil},
               {:identifier, 'foo'}
             ] = tokens
    end

    test "consumes as many tokens as it can" do
      tokens =
        "String.tri|"
        |> new_env()
        |> prefix_tokens(900)

      assert [{:identifier, 'tri'}, {:operator, :.}, {:alias, 'String'}] = tokens
    end

    test "works with macros" do
      tokens =
        "defmacro MyModule do"
        |> new_env()
        |> prefix_tokens(3)

      assert tokens == [
               {:operator, :do},
               {:alias, 'MyModule'},
               {:identifier, 'defmacro'}
             ]
    end

    test "works with lists of integers" do
      tokens =
        "x = [1, 2, 3]"
        |> new_env()
        |> prefix_tokens(7)

      assert tokens == [
               {:operator, :"]"},
               {:int, 3},
               {:comma, :","},
               {:int, 2},
               {:comma, :","},
               {:int, 1},
               {:operator, :"["}
             ]
    end
  end

  describe "in_bitstring?/1" do
    test "is true if the reference starts in a bitstring at the start of a line" do
      env = new_env("<<|")
      assert in_bitstring?(env)
    end

    test "is true if the reference starts in a bitstring with matches" do
      env = new_env("<<foo::|")
      assert in_bitstring?(env)

      env = new_env("<<foo::uint32, ba|")
      assert in_bitstring?(env)

      env = new_env("<<foo::uint32, bar::|")
      assert in_bitstring?(env)
    end

    test "is false if the position is outside a bitstring match on the same line" do
      env = new_env("<<foo::utf8>>|")
      refute in_bitstring?(env)

      env = new_env("<<foo::utf8>> = |")
      refute in_bitstring?(env)

      env = new_env("<<foo::utf8>> = str|")
      refute in_bitstring?(env)
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
