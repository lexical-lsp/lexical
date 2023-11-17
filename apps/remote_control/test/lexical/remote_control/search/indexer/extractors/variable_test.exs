defmodule Lexical.RemoteControl.Search.Indexer.Extractors.VariableTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.Test.RangeSupport

  import Lexical.Test.CodeSigil
  import RangeSupport

  use ExUnit.Case, async: true

  def index(source, filter \\ []) do
    only_definition? = Keyword.get(filter, :definition?, false)

    path = "/foo/bar/baz.ex"
    doc = Document.new("file:///#{path}", source, 1)

    case Indexer.Source.index("/foo/bar/baz.ex", source) do
      {:ok, indexed_items} ->
        items =
          if only_definition? do
            Enum.filter(indexed_items, fn item ->
              item.type == :variable and item.subtype == :definition
            end)
          else
            Enum.filter(indexed_items, fn item ->
              item.type == :variable
            end)
          end

        {:ok, items, doc}

      error ->
        error
    end
  end

  describe "indexing definition of variable assignment" do
    test "simple assignment" do
      {:ok, [variable], doc} = ~q[
        a = 1
      ] |> index()

      assert variable.type == :variable
      assert variable.subject == :a
      assert variable.subtype == :definition

      assert decorate(doc, variable.range) =~ "«a» = 1"
    end

    test "multiple assignments with `Tuple` in one line" do
      {:ok, [a, b], doc} = ~q[
        {a, b} = {1, 2}
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a», b}"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "{a, «b»}"
    end

    test "multiple assignments with `tuple` in multiple lines" do
      {:ok, [a, b], doc} = ~q[
        {a,
         b} =
          {1, 2}
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a»,"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "«b»}"
    end

    test "multiple assignments with `list`" do
      {:ok, [a, b], doc} = ~q(
        [a, b] = [1, 2]
      ) |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "[«a», b]"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "[a, «b»]"
    end

    test "nested assignments" do
      {:ok, [a, b], doc} = ~q(
        {a, [b]} = {1, [2]}
      ) |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "{«a», [b]}"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "{a, [«b»]}"
    end

    test "multiple assignments with `map`" do
      {:ok, [foo, bar], doc} = ~q(
        %{foo: foo, bar: bar} = %{foo: 1, bar: 2}
      ) |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "%{foo: «foo», bar: bar}"

      assert bar.subject == :bar
      assert decorate(doc, bar.range) =~ "%{foo: foo, bar: «bar»}"
    end

    test "nested assignments with `map`" do
      {:ok, [foo, sub_foo], doc} = ~q(
      %{foo: foo, bar: %{sub_foo: sub_foo}} = %{foo: 1, bar: %{sub_foo: 2, sub_bar: 3}}
      ) |> index()

      assert foo.subject == :foo

      assert decorate(doc, foo.range) =~
               "%{foo: «foo», bar: %{sub_foo: sub_foo}}"

      assert sub_foo.subject == :sub_foo

      assert decorate(doc, sub_foo.range) =~
               "%{foo: foo, bar: %{sub_foo: «sub_foo»}}"
    end

    test "assignment with `struct`" do
      {:ok, [foo], doc} = ~q(
        %Foo{foo: foo} = %Foo{foo: 1, bar: 2}
      ) |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "%Foo{foo: «foo»}"
    end

    test "assignment with current module's `struct`" do
      {:ok, [foo], doc} = ~q(
        %__MODULE__{foo: foo} = %__MODULE__{foo: 1, bar: 2}
      ) |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "%__MODULE__{foo: «foo»}"
    end

    test "assignments with multiple `=`" do
      {:ok, [value, struct_variable], doc} = ~q(
        %Foo{field: value} = foo = %Foo{field: 1}
      ) |> index()

      assert value.subject == :value
      assert decorate(doc, value.range) =~ "%Foo{field: «value»}"

      assert struct_variable.subject == :foo
      assert decorate(doc, struct_variable.range) =~ "«foo» = %Foo{field: 1}"
    end
  end

  describe "variable usages" do
    test "simple usage" do
      {:ok, [definition, usage], doc} = ~q/
        a = 1
        [a]
      / |> index()

      assert definition.subject == :a
      assert decorate(doc, definition.range) =~ "«a» = 1"
      assert definition.subtype == :definition

      assert usage.subject == :a
      assert decorate(doc, usage.range) =~ "[«a»]"
      assert usage.subtype == :reference
      assert usage.parent == definition.ref
    end

    test "usages in if" do
      {:ok, [definition, usage, another_usage], doc} = ~q/
        a = 1
        if true do
          a
        else
          [a]
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» = 1"

      assert decorate(doc, usage.range) =~ "  «a»"
      assert decorate(doc, another_usage.range) =~ "[«a»]"

      assert usage.parent == definition.ref
      assert another_usage.parent == definition.ref
    end

    test "it doesn't confuse same name variables in diffrent blocks" do
      assert {:ok, [def1_in_root, def2_in_root, def_in_if, usage_in_if, usage_in_root], doc} = ~q/
        a = 1
        a = 2
        if true do
          a = 3
          {a, 1}
        end
        [a]
      / |> index()

      assert decorate(doc, def1_in_root.range) =~ "«a» = 1"
      assert decorate(doc, def2_in_root.range) =~ "«a» = 2"
      assert decorate(doc, def_in_if.range) =~ "«a» = 3"

      assert decorate(doc, usage_in_if.range) =~ "«a», 1"
      assert usage_in_if.parent == def_in_if.ref

      assert decorate(doc, usage_in_root.range) =~ "[«a»]"
      assert usage_in_root.parent == def2_in_root.ref
    end

    @tag :skip
    test "usages in `else`" do
      {:ok, [definition, def_in_if, usage_in_if, usage_in_else], doc} = ~q/
        a = 1
        if false do
          a = 2
          {a, 2}
        else
          [a]
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» = 1"
      assert decorate(doc, def_in_if.range) =~ "«a» = 2"
      assert decorate(doc, usage_in_if.range) =~ "{«a», 2}"
      assert usage_in_if.parent == def_in_if.ref

      assert decorate(doc, usage_in_else.range) =~ "[«a»]"
      # we need to build scope for this kind of usage in `else`
      assert usage_in_else.parent == :root
    end

    test "usages in case" do
      {:ok, [definition, usage, another_usage], doc} = ~q/
        a = 1
        case a do
          1 -> :ok
          2 -> a
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» = 1"

      assert decorate(doc, usage.range) =~ "case «a» do"
      assert decorate(doc, another_usage.range) =~ "-> «a»"

      assert usage.parent == definition.ref
      assert another_usage.parent == definition.ref
    end

    test "usages in cond" do
      {:ok, [definition, usage, another_usage, usage_after_arrow], doc} = ~q/
        a = 1
        cond do
          a == 1 -> :ok
          a == 2 -> a
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» = 1"
      assert decorate(doc, usage.range) =~ "«a» == 1 ->"
      assert decorate(doc, another_usage.range) =~ "«a» == 2 ->"
      assert decorate(doc, usage_after_arrow.range) =~ "-> «a»"

      assert usage_after_arrow.parent == definition.ref
    end
  end

  describe "variables in the function header" do
    test "no variables in the parameter list" do
      assert {:ok, [], _doc} = ~q[
        def foo do
        end
      ] |> index()
    end

    test "in parameter list" do
      {:ok, [a, b], doc} = ~q[
        def foo(a, b) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(«a», b)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "def foo(a, «b»)"
    end

    test "in a private function's parameter list" do
      {:ok, [a, b], doc} = ~q[
        defp foo(a, b) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "defp foo(«a», b)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "defp foo(a, «b»)"
    end

    test "in parameter list with default value" do
      {:ok, [a, b], doc} = ~q[
        def foo(a, b \\ 2) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(«a», b \\\\ 2)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "def foo(a, «b» \\\\ 2)"
    end

    test "in parameter list but on the right side" do
      {:ok, [a, b], doc} = ~q[
        def foo(:a = a, 1 = b) do
        end
      ] |> index()

      assert a.subject == :a
      assert decorate(doc, a.range) =~ "def foo(:a = «a», 1 = b)"

      assert b.subject == :b
      assert decorate(doc, b.range) =~ "def foo(:a = a, 1 = «b»)"
    end

    test "multiple variables with nested structure" do
      assert {:ok, [var_d, var_a, var_b, var_c], doc} = ~q/
        def myfunc({:a, a, [b, c]} = d) do
        end
      / |> index()

      assert decorate(doc, var_d.range) =~ "def myfunc({:a, a, [b, c]} = «d»)"
      assert decorate(doc, var_a.range) =~ "def myfunc({:a, «a», [b, c]} = d)"
      assert decorate(doc, var_b.range) =~ "def myfunc({:a, a, [«b», c]} = d)"
      assert decorate(doc, var_c.range) =~ "def myfunc({:a, a, [b, «c»]} = d)"
    end

    test "matching struct in parameter list" do
      {:ok, [foo, value], doc} = ~q[
        def func(%Foo{field: value}=foo) do
        end
      ] |> index()

      assert foo.subject == :foo
      assert decorate(doc, foo.range) =~ "def func(%Foo{field: value}=«foo»)"

      assert value.subject == :value
      assert decorate(doc, value.range) =~ "def func(%Foo{field: «value»}=foo)"
    end
  end

  describe "usages of the function params" do
    test "simple usages" do
      {:ok, [definition, usage], doc} = ~q/
        def foo(a) do
          a
        end
      / |> index()

      assert definition.subject == :a
      assert decorate(doc, definition.range) =~ "def foo(«a»)"

      assert usage.subject == :a
      assert decorate(doc, usage.range) =~ "«a»"
      assert usage.parent == definition.ref
    end

    test "usage after `when`" do
      {:ok, [definition, usage], doc} = ~q/
        def foo(a) when is_integer(a) do
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "def foo(«a») when is_integer(a)"

      assert decorate(doc, usage.range) =~ "is_integer(«a»)"
      assert usage.parent == definition.ref
    end

    test "multiple usages after `when`" do
      {:ok, [definition, usage1, usage2], doc} = ~q/
        def foo(a) when is_integer(a) and a > 1 do
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "def foo(«a») when is_integer(a) and a > 1"
      assert decorate(doc, usage1.range) =~ "is_integer(«a»)"
      assert decorate(doc, usage2.range) =~ "«a» > 1"

      assert usage1.parent == definition.ref
      assert usage2.parent == definition.ref
    end

    test "shouldn't confuse with the same name variables in different functions" do
      assert {:ok,
              [
                def1_in_foo_function_params,
                def2_in_foo_function_block,
                usage_in_foo_function_block,
                def_in_bar_function_params,
                usage_in_bar_function_block
              ], doc} = ~q/
        def foo(a) do
          a = 2
          {a, 2}
        end

        def bar(a) do
          [a]
        end
      / |> index()

      assert decorate(doc, def1_in_foo_function_params.range) =~ "def foo(«a»)"
      assert decorate(doc, def2_in_foo_function_block.range) =~ "«a» = 2"
      assert decorate(doc, usage_in_foo_function_block.range) =~ "{«a», 2}"
      assert usage_in_foo_function_block.parent == def2_in_foo_function_block.ref

      assert decorate(doc, def_in_bar_function_params.range) =~ "def bar(«a»)"
      assert decorate(doc, usage_in_bar_function_block.range) =~ "[«a»]"
    end
  end

  describe "definition in anonymous function" do
    test "simple anonymous function" do
      {:ok, [definition], doc} = ~q/
        fn
          a -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert definition.subtype == :definition
      refute definition.parent == :root
    end

    test "matching list" do
      {:ok, [definition], doc} = ~q/
        fn
          [a] -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "[«a»] ->"
      refute definition.parent == :root
    end

    test "matching map" do
      {:ok, [definition], doc} = ~q/
        fn
          %{a: a} -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "%{a: «a»} ->"
      refute definition.parent == :root
    end

    test "matching tuple" do
      assert {:ok, [def_a, def_b], doc} = ~q/
        fn
          {a, b} -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, def_a.range) =~ "{«a», b} ->"
      assert decorate(doc, def_b.range) =~ "{a, «b»} ->"

      refute def_a.parent == :root
      refute def_b.parent == :root
    end

    test "matching list of tuples" do
      {:ok, [def_a, def_b], doc} = ~q/
        fn
          [{a, b}] -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, def_a.range) =~ "[{«a», b}] ->"
      assert decorate(doc, def_b.range) =~ "[{a, «b»}] ->"

      refute def_a.parent == :root
      refute def_b.parent == :root
    end

    test "matching tuple of lists" do
      {:ok, [definition], doc} = ~q/
        fn
          {[a]} -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "{[«a»]} ->"
      refute definition.parent == :root
    end

    test "matching tuple of tuples" do
      {:ok, [def_a, def_b], doc} = ~q/
        fn
          {{a, b}} -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, def_a.range) =~ "{{«a», b}} ->"
      assert decorate(doc, def_b.range) =~ "{{a, «b»}} ->"

      refute def_a.parent == :root
      refute def_b.parent == :root
    end

    test "matching struct" do
      {:ok, [definition], doc} = ~q/
        fn
          %Foo{field: value} -> value
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "%Foo{field: «value»} ->"
      refute definition.parent == :root
    end

    test "at `=`'s right side" do
      {:ok, [definition], doc} = ~q/
        fn
          1 = a -> a
        end
      / |> index(definition?: true)

      assert decorate(doc, definition.range) =~ "1 = «a» ->"
      refute definition.parent == :root
    end
  end

  describe "usages in anonymous function" do
    test "simple usage" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> a
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"

      assert decorate(doc, usage.range) =~ "-> «a»"
      assert usage.parent == definition.ref
    end

    test "no usage at the right side" do
      assert {:ok, [definition], doc} = ~q/
        fn
          a -> 1
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
    end

    test "uses the parent defintion" do
      {:ok, [definition, usage], doc} = ~q/
        a = 1
        fn -> a end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» = 1"
      assert decorate(doc, usage.range) =~ "-> «a»"
      assert usage.parent == definition.ref
    end

    test "usage after `when`" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a when a > 0 -> :ok
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» when a > 0 ->"
      assert decorate(doc, usage.range) =~ "when «a» > 0"
    end

    test "usage after `when` with multiple conditions" do
      {:ok, [definition, usage1, usage2], doc} = ~q/
        fn
          a when a > 0 and a < 1 -> :ok
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» when a > 0 and a < 1 ->"

      assert decorate(doc, usage1.range) =~ "when «a» > 0"
      assert decorate(doc, usage2.range) =~ "and «a» < 1"

      assert usage1.parent == definition.ref
      assert usage2.parent == definition.ref
    end

    test "uses the field vaule after `when`" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          %Foo{field: a} when a > 0 -> :ok
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "%Foo{field: «a»} when a > 0 ->"
      assert decorate(doc, usage.range) =~ "when «a» > 0"

      assert usage.parent == definition.ref
    end

    test "usage in a list" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> [a]
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "[«a»]"

      assert usage.parent == definition.ref
    end

    test "usage in a map" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> %{a: a}
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "%{a: «a»}"
    end

    test "usage in a list of tuples" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> [{a, 1}]
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "[{«a», 1}]"
    end

    test "usage in a list of lists" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> [[a]]
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "[[«a»]]"
    end

    test "usage in a tuple of lists" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> {[a]}
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "{[«a»]}"
    end

    test "usage in a tuple of tuples" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> {{a, 1}}
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "{{«a», 1}}"
    end

    test "usage in a call" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> a.(1)
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "«a».(1)"
    end

    test "usage in a map value" do
      {:ok, [definition, usage], doc} = ~q/
        fn
          a -> %{b: :another_value, a: a}
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "%{b: :another_value, a: «a»}"
    end

    test "usage when the right side having multiple lines" do
      {:ok, [definition, usage, another_definition, another_usage], doc} = ~q/
        fn
          a ->
            a
            |> Enum.map(fn a -> a end)
        end
      / |> index()

      assert decorate(doc, definition.range) =~ "«a» ->"
      assert decorate(doc, usage.range) =~ "    «a»"
      assert usage.parent == definition.ref

      assert decorate(doc, another_definition.range) =~ "fn «a» ->"
      assert decorate(doc, another_usage.range) =~ "-> «a»"
      assert another_usage.parent == another_definition.ref
    end

    test "distinguish variables of the same name across scopes" do
      assert {:ok,
              [
                root_def_a,
                def_a,
                use_a,
                another_a,
                use_another_a,
                use_another_a_again,
                use_root_a
              ], doc} = ~q/
        a = 1
        fn
          %{} = a ->
            [1]
            a

          a ->
            {a, 1}
            [a]
        end
        %{root: a}
      / |> index()

      assert decorate(doc, def_a.range) =~ "%{} = «a» ->"
      assert decorate(doc, use_a.range) =~ "    «a»"
      assert use_a.parent == def_a.ref

      assert decorate(doc, another_a.range) =~ "  «a» ->"
      assert decorate(doc, use_another_a.range) =~ "{«a», 1}"
      assert use_another_a.parent == another_a.ref

      assert decorate(doc, use_another_a_again.range) =~ "[«a»]"
      assert use_another_a_again.parent == another_a.ref

      assert decorate(doc, root_def_a.range) =~ "«a» = 1"
      assert decorate(doc, use_root_a.range) =~ "%{root: «a»}"
      assert use_root_a.parent == root_def_a.ref
    end
  end
end
