defmodule Lexical.Server.CodeIntelligence.Completion.EnvTest do
  alias Lexical.Document
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.Server.CodeIntelligence.Completion
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport
  alias Lexical.Test.Fixtures

  use ExUnit.Case, async: true

  import CodeSigil
  import Completion.Env
  import CursorSupport
  import Fixtures

  def new_env(text) do
    project = project()
    {line, column} = cursor_position(text)
    stripped_text = strip_cursor(text)
    document = Document.new("file://foo.ex", stripped_text, 0)

    position = Document.Position.new(line, column)

    {:ok, env} = new(project, document, position)
    env
  end

  describe "prefix_tokens/2" do
    test "works with bitstring specifiers" do
      env = new_env("<<foo::int|")

      assert [{:identifier, 'int', _}, {:operator, :"::", _}] = prefix_tokens(env, 2)
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
               {:kw_identifier, 'a', _},
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
               {:identifier, 'map', _},
               {:operator, :., _},
               {:alias, 'Enum', _}
             ] = tokens
    end

    test "works with local function calls" do
      tokens =
        "foo = local(|"
        |> new_env()
        |> prefix_tokens(9)

      assert [
               {:paren, :"(", _},
               {:paren_identifier, 'local', _},
               {:match_op, nil, _},
               {:identifier, 'foo', _}
             ] = tokens
    end

    test "consumes as many tokens as it can" do
      tokens =
        "String.tri|"
        |> new_env()
        |> prefix_tokens(900)

      assert [
               {:identifier, 'tri', _},
               {:operator, :., _},
               {:alias, 'String', _}
             ] = tokens
    end

    test "works with macros" do
      tokens =
        "defmacro MyModule do"
        |> new_env()
        |> prefix_tokens(3)

      assert [
               {:operator, :do, _},
               {:alias, 'MyModule', _},
               {:identifier, 'defmacro', _}
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

  describe "in_context?(env, :struct_arguments)" do
    def my_module(text) do
      """
      defmodule MyModule do
        #{text}
      end
      """
    end

    def func_variable(text) do
      """
      def func do
        #{text}
      end
      """
    end

    def func_args(text) do
      """
      def func(#{text}) do
      end
      """
    end

    test "is true if the cursor after curly" do
      env = "%User{|}" |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is true when the struct is in the function variable" do
      env = "%User{|}" |> func_variable() |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is true when the struct is in the function arguments" do
      env = "%User{|}" |> func_args() |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is false when the cursor is not in a container" do
      env = new_env("%User{|}")
      refute in_context?(env, :struct_arguments)
    end

    test "is true if the cursor after the field name" do
      env = "%User{name: |}" |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is true if the cursor after the field value" do
      env = "%User{name: \"John\"|}" |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is true if the cursor starts in the middle of the struct" do
      env = "%User{name: \"John\", |}" |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is false if the cursor after the closing curly" do
      env = "%User{}|" |> my_module() |> new_env()
      refute in_context?(env, :struct_arguments)
    end

    test "is true if the cursor in current module arguments" do
      env = "%__MODULE__{|}" |> func_variable() |> my_module() |> new_env()
      assert in_context?(env, :struct_arguments)
    end

    test "is true even the struct alias is at the above line" do
      source = ~q[
        %User{
          name: "John",
          |
        }
      ]
      env = new_env(source)
      assert in_context?(env, :struct_arguments)
    end

    test "is true even if the value of a struct key is a tuple" do
      env = new_env("%User{favorite_numbers: {3}|")
      assert in_context?(env, :struct_arguments)
    end

    test "is true even if the cursor is at a nested struct" do
      env = new_env("%User{address: %Address{}|")
      assert in_context?(env, :struct_arguments)
    end
  end

  describe "in_context?(env, :value)" do
    test "is true if the cursor is after a value character" do
      env = new_env("%{foo: 1|}")
      assert in_context?(env, :value)
    end

    test "is ture if the cursor is after a colon" do
      env = new_env("%{foo: |}")
      assert in_context?(env, :value)
    end

    test "is false if the cursor is in a multiple lines key positon" do
      source = ~q[
        %{
          foo: 1,
          |
        }
      ]

      env = new_env(source)
      refute in_context?(env, :value)
    end
  end

  describe "in_context?(env, :struct_reference)" do
    test "is true if the reference starts on the beginning of the line" do
      env = new_env("%User|")
      assert in_context?(env, :struct_reference)
    end

    test "is false if the cursor in curly" do
      env = new_env("%User{|}")
      refute in_context?(env, :struct_reference)
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

  describe "strip_struct_reference/1" do
    test "with a reference followed by  __" do
      {doc, _position} =
        "%__"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "__"
    end

    test "with a reference followed by a module name" do
      {doc, _position} =
        "%Module"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "Module"
    end

    test "with a reference followed by a module and a dot" do
      {doc, _position} =
        "%Module."
        |> new_env()
        |> strip_struct_reference()

      assert doc == "Module."
    end

    test "with a reference followed by a nested module" do
      {doc, _position} =
        "%Module.Sub"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "Module.Sub"
    end

    test "with a reference followed by an alias" do
      code = ~q[
        alias Something.Else
        %El|
      ]t

      {doc, _position} =
        code
        |> new_env()
        |> strip_struct_reference()

      assert doc == "alias Something.Else\nEl"
    end

    test "on a line with two references, replacing the first" do
      {doc, _position} =
        "%First{} = %Se"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "%First{} = Se"
    end

    test "on a line with two references, replacing the second" do
      {doc, _position} =
        "%Fir| = %Second{}"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "Fir = %Second{}"
    end

    test "with a plain module" do
      env = new_env("Module")
      {doc, _position} = strip_struct_reference(env)

      assert doc == env.document
    end

    test "with a plain module strip_struct_reference a dot" do
      env = new_env("Module.")
      {doc, _position} = strip_struct_reference(env)

      assert doc == env.document
    end

    test "leaves leading spaces in place" do
      {doc, _position} =
        "     %Some"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "     Some"
    end

    test "works in a function definition" do
      {doc, _position} =
        "def my_function(%Lo|)"
        |> new_env()
        |> strip_struct_reference()

      assert doc == "def my_function(Lo)"
    end
  end

  def item(label, opts \\ []) do
    opts
    |> Keyword.merge(label: label)
    |> CompletionItem.new()
    |> boost(0)
  end

  defp sort_items(items) do
    Enum.sort_by(items, &{&1.sort_text, &1.label})
  end

  describe "boosting" do
    test "default boost sorts things first" do
      alpha_first = item("a")
      alpha_last = "z" |> item() |> boost()

      assert [^alpha_last, ^alpha_first] = sort_items([alpha_first, alpha_last])
    end

    test "local boost allows you to specify the order" do
      alpha_first = "a" |> item() |> boost(1)
      alpha_second = "b" |> item() |> boost(2)
      alpha_third = "c" |> item() |> boost(3)

      assert [^alpha_third, ^alpha_second, ^alpha_first] =
               sort_items([alpha_first, alpha_second, alpha_third])
    end

    test "global boost overrides local boost" do
      local_max = "a" |> item() |> boost(9)
      global_min = "z" |> item() |> boost(0, 1)

      assert [^global_min, ^local_max] = sort_items([local_max, global_min])
    end

    test "items can have a global and local boost" do
      group_b_min = "a" |> item() |> boost(1)
      group_b_max = "b" |> item() |> boost(2)
      group_a_min = "c" |> item |> boost(1, 1)
      group_a_max = "c" |> item() |> boost(2, 1)
      global_max = "d" |> item() |> boost(0, 2)

      items = [group_b_min, group_b_max, group_a_min, group_a_max, global_max]

      assert [^global_max, ^group_a_max, ^group_a_min, ^group_b_max, ^group_b_min] =
               sort_items(items)
    end
  end

  describe "prefix_alias_position/1" do
    test "when in current module" do
      source = ~q<
        defmodule User do
          defstruct [:name, :age]

          def name(%__MODULE__{|}) do
          end
        end
      >

      assert {4, 13} == source |> new_env() |> prefix_alias_position()
    end
  end
end
