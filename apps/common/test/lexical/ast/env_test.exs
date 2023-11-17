defmodule Lexical.Ast.EnvTest do
  use ExUnit.Case, async: true

  alias Lexical.Ast

  import Lexical.Ast.Env
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures

  def new_env(text, opts \\ []) do
    opts = Keyword.merge([as: :document], opts)
    project = project()
    {position, document} = pop_cursor(text, opts)
    analysis = Ast.analyze(document)
    {:ok, env} = new(project, analysis, position)
    env
  end

  describe "prefix_tokens/2" do
    test "works with bitstring specifiers" do
      env = new_env("<<foo::int|")

      assert [{:identifier, ~c"int", _}, {:operator, :"::", _}] = prefix_tokens(env, 2)
    end

    test "works with floats" do
      tokens =
        "27.88"
        |> new_env()
        |> prefix_tokens(1)

      assert [{:float, 27.88, _}] = tokens
    end

    test "works with strings" do
      tokens =
        ~s("hello")
        |> new_env()
        |> prefix_tokens(1)

      assert [{:string, "hello", _}] = tokens
    end

    test "works with interpolated strings" do
      tokens =
        ~S("hello#{a}")
        |> new_env()
        |> prefix_tokens(1)

      assert [{:interpolated_string, ["hello" | _], _}] = tokens
    end

    test "works with maps with atom keys" do
      tokens =
        "%{a: 3}"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:curly, :"}", _},
               {:int, 3, _},
               {:kw_identifier, ~c"a", _},
               {:curly, :"{", _},
               {:map_new, :%{}, _}
             ] = tokens
    end

    test "works with maps with string keys" do
      tokens =
        ~s(%{"a" => 3})
        |> new_env()
        |> prefix_tokens(8)

      assert [
               {:curly, :"}", _},
               {:int, 3, _},
               {:assoc_op, nil, _},
               {:string, "a", _},
               {:curly, :"{", _},
               {:map_new, :%{}, _}
             ] = tokens
    end

    test "works with pattern matches" do
      tokens =
        "my_var = 3 + 5"
        |> new_env()
        |> prefix_tokens(3)

      assert [
               {:int, 5, _},
               {:operator, :+, _},
               {:int, 3, _}
             ] = tokens
    end

    test "works with remote function calls" do
      tokens =
        "Enum.map|"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:identifier, ~c"map", _},
               {:operator, :., _},
               {:alias, ~c"Enum", _}
             ] = tokens
    end

    test "works with local function calls" do
      tokens =
        "foo = local(|"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:paren, :"(", _},
               {:paren_identifier, ~c"local", _},
               {:match_op, nil, _},
               {:identifier, ~c"foo", _}
             ] = tokens
    end

    test "consumes as many tokens as it can" do
      tokens =
        "String.tri|"
        |> new_env()
        |> prefix_tokens(900)

      assert [
               {:identifier, ~c"tri", _},
               {:operator, :., _},
               {:alias, ~c"String", _}
             ] = tokens
    end

    test "works with macros" do
      tokens =
        "defmacro MyModule do"
        |> new_env()
        |> prefix_tokens(3)

      assert [
               {:operator, :do, _},
               {:alias, ~c"MyModule", _},
               {:identifier, ~c"defmacro", _}
             ] = tokens
    end

    test "works with lists of integers" do
      tokens =
        "x = [1, 2, 3]"
        |> new_env()
        |> prefix_tokens(7)

      assert [
               {:operator, :"]", _},
               {:int, 3, _},
               {:comma, :",", _},
               {:int, 2, _},
               {:comma, :",", _},
               {:int, 1, _},
               {:operator, :"[", _}
             ] = tokens
    end
  end
end
