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
end
