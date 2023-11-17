defmodule Lexical.Ast.EnvTest do
  use ExUnit.Case, async: true

  alias Lexical.Ast

  import Lexical.Ast.Env
  import Lexical.Test.CodeSigil
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

  describe "in_context?(env, :bitstring)" do
    test "is true if the reference starts in a bitstring at the start of a line" do
      env = new_env("<<|")
      assert in_context?(env, :bitstring)
    end

    test "is true if the reference starts in a bitstring with matches" do
      env = new_env("<<foo::|")
      assert in_context?(env, :bitstring)

      env = new_env("<<foo::uint32, ba|")
      assert in_context?(env, :bitstring)

      env = new_env("<<foo::uint32, bar::|")
      assert in_context?(env, :bitstring)
    end

    test "is false if the position is outside a bitstring match on the same line" do
      env = new_env("<<foo::utf8>>|")
      refute in_context?(env, :bitstring)

      env = new_env("<<foo::utf8>> = |")
      refute in_context?(env, :bitstring)

      env = new_env("<<foo::utf8>> = str|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :bitstring)
    end

    test "is false if in a pipe" do
      env = new_env("|> in_|")
      refute in_context?(env, :bitstring)
    end
  end

  describe "in_context?(env, :struct_fields)" do
    def wrap_with_module(text) do
      """
      defmodule MyModule do
        #{text}
      end
      """
    end

    def wrap_with_function(text) do
      """
      def func do
        #{text}
      end
      """
    end

    def wrap_with_function_arguments(text) do
      """
      def func(#{text}) do
      end
      """
    end

    test "is true if the cursor is directly after the opening curly" do
      env = "%User{|}" |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true when the struct is in the function variable" do
      env = "%User{|}" |> wrap_with_function() |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true when the struct is in the function arguments" do
      env = "%User{|}" |> wrap_with_function_arguments() |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true if the cursor is after the field name" do
      env = "%User{name: |}" |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true if the cursor is after the field value" do
      env = "%User{name: \"John\"|}" |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true if the cursor starts in the middle of the struct" do
      env = "%User{name: \"John\", |}" |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is false if the cursor is after the closing curly" do
      env = "%User{}|" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_fields)
    end

    test "is true if the cursor is in current module arguments" do
      env = "%__MODULE__{|}" |> wrap_with_function() |> wrap_with_module() |> new_env()
      assert in_context?(env, :struct_fields)
    end

    test "is true if the struct alias spans multiple lines" do
      source = ~q[
        %User{
          name: "John",
          |
        }
      ]
      env = new_env(source)
      assert in_context?(env, :struct_fields)
    end

    test "is true even if the value of a struct key is a tuple" do
      env = new_env("%User{favorite_numbers: {3}|")
      assert in_context?(env, :struct_fields)
    end

    test "is true even if the cursor is at a nested struct" do
      env = new_env("%User{address: %Address{}|")
      assert in_context?(env, :struct_fields)
    end

    test "is false if the cursor is in a map" do
      env = "%{|field: value}" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_fields)
    end
  end

  describe "in_context?(env, :struct_field_value)" do
    test "is true if the cursor is after a value character" do
      env = new_env("%User{foo: 1|}")
      assert in_context?(env, :struct_field_value)
    end

    test "is true if the cursor is after a colon" do
      env = new_env("%User{foo: |}")
      assert in_context?(env, :struct_field_value)
    end

    test "is false if the cursor is in a multiple lines key positon" do
      source = ~q[
        %User{
          foo: 1,
          |
        }
      ]

      env = new_env(source)
      refute in_context?(env, :struct_field_value)
    end

    test "is false in static keywords" do
      env = "[foo: |]" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_value)
    end

    test "is false when is in static keywords and starts with a character" do
      env = "[foo: :a|]" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_value)
    end

    test "is false in map field value position" do
      env = "%{foo: |}" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_value)
    end
  end

  describe "in_context?(env, :struct_field_key)" do
    test "is true if the cursor is after the struct opening" do
      env = new_env("%User{|}")
      assert in_context?(env, :struct_field_key)
    end

    test "is true if a key is partially typed" do
      env = new_env("%User{fo|}")
      assert in_context?(env, :struct_field_key)
    end

    test "is true if after a comma" do
      env = new_env("%User{foo: 1, |}")
      assert in_context?(env, :struct_field_key)
    end

    test "is true if after a comma on another line" do
      source = ~q[
        %User{
          foo: 1,
          |
        }
      ]

      env = new_env(source)
      assert in_context?(env, :struct_field_key)
    end

    test "is false in static keywords" do
      env = "[fo|]" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_key)
    end

    test "is false in static keywords nested in a struct" do
      env = "%User{foo: [fo|]}" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_key)
    end

    test "is false in map field key position" do
      env = "%{|}" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_key)
    end

    test "is false in map field key position nested in a struct" do
      env = "%User{foo: %{|}}" |> wrap_with_module() |> new_env()
      refute in_context?(env, :struct_field_key)
    end
  end

  describe "in_context?(env, :struct_reference)" do
    test "is true if the reference starts on the beginning of the line" do
      env = new_env("%User|")
      assert in_context?(env, :struct_reference)
    end

    test "is true if the reference starts in function arguments" do
      env = new_env("def my_function(%Use|)")
      assert in_context?(env, :struct_reference)
    end

    test "is true if a module reference starts in function arguments" do
      env = new_env("def my_function(%_|)")
      assert in_context?(env, :struct_reference)
    end

    test "is ture if a module reference start in a t type spec" do
      env = new_env("@type t :: %_|")
      assert in_context?(env, :struct_reference)
    end

    test "is false if module reference not starts with %" do
      env = new_env("def something(my_thing|, %Struct{})")
      refute in_context?(env, :struct_reference)
    end

    test "is true if the reference is for %__MOD in a function definition " do
      env = new_env("def my_fn(%__MOD")
      assert in_context?(env, :struct_reference)
    end

    test "is false if the reference is for %__MOC in a function definition" do
      env = new_env("def my_fn(%__MOC)")
      refute in_context?(env, :struct_reference)
    end

    test "is false if a module reference lacks a %" do
      env = new_env("def my_function(__|)")
      refute in_context?(env, :struct_reference)
    end

    test "is true if the reference is on the right side of a match" do
      env = new_env("foo = %Use|")
      assert in_context?(env, :struct_reference)
    end

    test "is true if the reference is on the left side of a match" do
      env = new_env(" %Use| = foo")
      assert in_context?(env, :struct_reference)
    end

    test "is true if the reference is for %__} " do
      env = new_env("%__")
      assert in_context?(env, :struct_reference)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :struct_reference)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :struct_reference)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :struct_reference)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :struct_reference)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :struct_reference)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :struct_reference)
    end
  end

  describe "in_context?(env, :function_capture)" do
    test "is true for arity one local functions" do
      env = new_env("&is_map|")
      assert in_context?(env, :function_capture)
    end

    test "is true for arity two local functions with a variable" do
      env = new_env("&is_map_key(&1, l|)")
      assert in_context?(env, :function_capture)
    end

    test "is true if the capture starts at the beginning of the line" do
      env = new_env("&Enum")
      assert in_context?(env, :function_capture)
    end

    test "is true if the capture is inside a function call" do
      env = new_env("list = Enum.map(1..10, &Enum|)")
      assert in_context?(env, :function_capture)
    end

    test "is true if the capture is inside an unformatted function call" do
      env = new_env("list = Enum.map(1..10,&Enum|)")
      assert in_context?(env, :function_capture)
    end

    test "is true if the capture is inside a function call after the dot" do
      env = new_env("list = Enum.map(1..10, &Enum.f|)")
      assert in_context?(env, :function_capture)
    end

    test "is true if the capture is in the body of a for" do
      env = new_env("for x <- Enum.map(1..10, &String.|)")
      assert in_context?(env, :function_capture)
    end

    test "is false if the position is after a capture with no arguments" do
      env = new_env("&something/1|")
      refute in_context?(env, :function_capture)
    end

    test "is false if the position is after a capture with arguments" do
      env = new_env("&captured(&1, :foo)|")
      refute in_context?(env, :function_capture)
    end

    test "is false if the capture starts at the beginning of the line" do
      env = new_env("Enum|")
      refute in_context?(env, :function_capture)
    end

    test "is false if the capture is inside a function call" do
      env = new_env("list = Enum.map(1..10, Enum|)")
      refute in_context?(env, :function_capture)
    end

    test "is false if the capture is inside an unformatted function call" do
      env = new_env("list = Enum.map(1..10,Enum|)")
      refute in_context?(env, :function_capture)
    end

    test "is false if the capture is inside a function call after the dot" do
      env = new_env("list = Enum.map(1..10, Enum.f|)")
      refute in_context?(env, :function_capture)
    end

    test "is false if the capture is in the body of a for" do
      env = new_env("for x <- Enum.map(1..10, String.|)")
      refute in_context?(env, :function_capture)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :function_capture)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :function_capture)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :function_capture)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :function_capture)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :function_capture)
    end

    test "is false if in a pipe" do
      env = new_env("|> MyThing.|")
      refute in_context?(env, :function_capture)
    end
  end

  describe "in_context?(env, :pipe)" do
    test "is true if the pipe is on the start of the line" do
      env = new_env("|> foo|()")
      assert in_context?(env, :pipe)
    end

    test "is true if the pipe is in a function call" do
      env = new_env("foo( a |> b |> c|)")
      assert in_context?(env, :pipe)
    end

    test "is true if the pipe is in a remote function call" do
      env = new_env("[] |> Enum.|")
      assert in_context?(env, :pipe)
    end

    test "is true if we're in a remote erlang call" do
      env = new_env("[] |> :string.|")
      assert in_context?(env, :pipe)
    end

    test "is false if the pipe is in a function call and the cursor is outside it" do
      env = new_env("foo( a |> b |> c)|")
      refute in_context?(env, :pipe)
    end

    test "is false if there is no pipe in the string" do
      env = new_env("Enum.|foo")
      refute in_context?(env, :pipe)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :pipe)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :pipe)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :pipe)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :pipe)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :pipe)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :pipe)
    end
  end

  describe "in_context?(env, :type)" do
    test "should be true right after the type" do
      env = new_env("@type |")
      assert in_context?(env, :type)
    end

    test "should be true if you're in a type definition" do
      env = new_env("@type my_type :: :mine")
      assert in_context?(env, :type)
    end

    test "should be true if you're in a composite type definition" do
      env = new_env("@type my_type :: :yours | :mine | :the_truth")
      assert in_context?(env, :type)
    end

    test "should work on a multi-line type definition" do
      env =
        new_env(
          ~q[
            @type on_multiple_lines ::
            integer()
            | String.t()
            | Something.t() !
          ],
          cursor: "!"
        )

      assert in_context?(env, :type)
    end

    test "should work on private types" do
      env = new_env("@typep private :: integer()")
      assert in_context?(env, :type)
    end

    test "should work on opaque types" do
      env = new_env("@opaque private :: integer()")
      assert in_context?(env, :type)
    end

    test "is false if the cursor is just after the type" do
      env = new_env(~q[
            @type my_type :: atom()
            |
          ])
      refute in_context?(env, :type)
    end

    test "is false if the cursor is just after the type without a block" do
      env = new_env("@type my_type :: atom()\nsomething()|\n")
      refute in_context?(env, :type)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :type)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :type)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :type)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :type)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :type)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :type)
    end

    test "is false if you're in a variable named type" do
      env = new_env("type = 3")
      refute in_context?(env, :type)
    end
  end

  describe "in_context?(env, :spec)" do
    test "should be true right after the spec" do
      env = new_env("@spec ")
      assert in_context?(env, :spec)
    end

    test "should be true if you're in a typespec" do
      env = new_env("@spec function_name(String.t) :: any()")
      assert in_context?(env, :spec)
    end

    test "should be true if you're in a composite spec definition" do
      env = new_env("@spec my_spec :: :yours | :mine | :the_truth")
      assert in_context?(env, :spec)
    end

    test "should work on a multi-line spec definition" do
      env =
        new_env(
          ~q[
        @spec on_multiple_lines :: integer()
        | String.t()
        | Something.t() !
        ],
          cursor: "!"
        )

      assert in_context?(env, :spec)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :spec)
    end

    test "is false if in an alias" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :spec)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :spec)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :spec)
    end

    test "is false if in a use" do
      env = new_env("alias MyModule.Othe|")
      refute in_context?(env, :spec)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :spec)
    end

    test "is false if you're in a variable named spec" do
      env = new_env("spec = 3")
      refute in_context?(env, :spec)
    end
  end

  describe "in_context?(env, :alias)" do
    test "should be true if this is a single alias" do
      env = new_env("alias MyThing.Other")
      assert in_context?(env, :alias)
    end

    test "should be true if this is an alias using as" do
      env = new_env("alias MyThing.Other, as: AnotherThing")
      assert in_context?(env, :alias)
    end

    test "should be true if this is a multiple alias on one line" do
      env = new_env("alias MyThing.{Foo, Bar, Ba|}")
      assert in_context?(env, :alias)
    end

    test "should be true if this is a multiple alias on multiple lines" do
      env =
        ~q[
        alias Foo.{
          Bar,
          Baz|
        }
        ]t
        |> new_env()

      assert in_context?(env, :alias)
    end

    test "should be false if the statement is not an alias" do
      env = new_env("x = %{foo: 3}|")
      refute in_context?(env, :alias)

      env = new_env("x = %{foo: 3|}")
      refute in_context?(env, :alias)
    end

    test "should be false if this is after a multiple alias on one line" do
      env = new_env("alias MyThing.{Foo, Bar, Baz}|")
      refute in_context?(env, :alias)
    end

    test "should be false if this is after a multiple alias on multiple lines" do
      env =
        ~q[
        alias Foo.{
          Bar,
          Baz
        }|
        ]t
        |> new_env()

      refute in_context?(env, :alias)
    end

    test "should be false if this is after a multiple alias on multiple lines (second form)" do
      env =
        ~q[
        alias Foo.{ Bar,
          Baz
        }|
        ]t
        |> new_env()

      refute in_context?(env, :alias)
    end

    test "should be false if this is after a multiple alias on multiple lines (third form)" do
      env =
        ~q[
        alias Foo.{ Bar, Baz
        }|
        ]t
        |> new_env()

      refute in_context?(env, :alias)
    end

    test "is false if there is nothing after the alias call" do
      env = new_env("alias|")
      refute in_context?(env, :alias)
    end

    test "is false if the alias is on another line" do
      env =
        ~q[
        alias Something.Else
        Macro.|
        ]t
        |> new_env()

      refute in_context?(env, :alias)
    end

    test "is false if in a function capture" do
      env = new_env("&MyModule.fun|")
      refute in_context?(env, :alias)
    end

    test "is false if in an import" do
      env = new_env("import MyModule.Othe|")
      refute in_context?(env, :alias)
    end

    test "is false if in a require" do
      env = new_env("require MyModule.Othe|")
      refute in_context?(env, :alias)
    end

    test "is false if in a use" do
      env = new_env("use MyModule.Othe|")
      refute in_context?(env, :alias)
    end

    test "is false if in a bitstring" do
      env = new_env("<< foo::in|")
      refute in_context?(env, :alias)
    end

    test "is false if in a pipe" do
      env = new_env("|> MyThing.|")
      refute in_context?(env, :alias)
    end
  end
end
