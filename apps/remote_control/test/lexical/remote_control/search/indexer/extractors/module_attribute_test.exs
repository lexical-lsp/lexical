defmodule Lexical.RemoteControl.Search.Indexer.Extractors.ModuleAttributeTest do
  alias Lexical.RemoteControl.Search.Subject
  use Lexical.Test.ExtractorCase

  def index(source) do
    do_index(source, fn entry ->
      entry.type == :module_attribute
    end)
  end

  describe "indexing module attributes" do
    test "finds definitions when defining scalars" do
      {:ok, [attr], doc} =
        ~q[
        defmodule Root do
         @attribute 32
        end
      ]
        |> index()

      assert attr.type == :module_attribute
      assert attr.subtype == :definition
      assert attr.subject == Subject.module_attribute(Root, :attribute)

      assert decorate(doc, attr.range) =~ "«@attribute 32»"
    end

    test "in-progress module attributes are ignored" do
      {:ok, [latter_attribute], _doc} =
        ~q[
        defmodule Root do
          @
          @callback foo() :: :ok
        end
        ]
        |> index()

      assert latter_attribute.subject == "@callback"
    end

    test "finds multiple definitions of the same attribute" do
      {:ok, [first, second, third], doc} =
        ~q[
          defmodule Parent do
           @tag 1
           def first,  do: 1

           @tag 2
           def second,  do: 1

           @tag 3
           def third,  do: 1
          end
        ]
        |> index()

      assert first.type == :module_attribute
      assert first.subtype == :definition
      assert first.subject == Subject.module_attribute(Parent, :tag)
      assert decorate(doc, first.range) =~ "«@tag 1»"

      assert second.type == :module_attribute
      assert second.subtype == :definition
      assert second.subject == Subject.module_attribute(Parent, :tag)
      assert decorate(doc, second.range) =~ "«@tag 2»"

      assert third.type == :module_attribute
      assert third.subtype == :definition
      assert third.subject == Subject.module_attribute(Parent, :tag)
      assert decorate(doc, third.range) =~ "«@tag 3»"
    end

    test "finds definitions when the definition spans multiple lines" do
      {:ok, [attr], doc} =
        ~q[
        defmodule Parent do
          @number_strings 1..50
            |> Enum.map(& &1 * 2)
            |> Enum.map(&Integer.to_string/1)
        end
        ]
        |> index()

      assert attr.type == :module_attribute
      assert attr.subtype == :definition
      assert attr.subject == Subject.module_attribute(Parent, :number_strings)

      expected =
        """
         «@number_strings 1..50
            |> Enum.map(& &1 * 2)
            |> Enum.map(&Integer.to_string/1)»
        """
        |> String.trim()

      assert decorate(doc, attr.range) =~ expected
    end

    test "finds references in other definitions" do
      {:ok, [_def1, def2, reference], doc} =
        ~q[
        defmodule Root do
           @attr 23

           @attr2 @attr + 1
        end
        ]
        |> index()

      assert def2.type == :module_attribute
      assert def2.subtype == :definition
      assert def2.subject == Subject.module_attribute(Root, :attr2)
      assert decorate(doc, def2.range) =~ "«@attr2 @attr + 1»"

      assert reference.type == :module_attribute
      assert reference.subtype == :reference
      assert reference.subject == Subject.module_attribute(Root, :attr)
      assert decorate(doc, reference.range) =~ "@attr2 «@attr» + 1"
    end

    test "finds definitions in nested contexts" do
      {:ok, [parent_def, child_def], doc} =
        ~q[
          defmodule Parent do
            @in_parent true
            defmodule Child do
              @in_child true
            end
          end
        ]
        |> index()

      assert parent_def.type == :module_attribute
      assert parent_def.subtype == :definition
      assert parent_def.subject == Subject.module_attribute(Parent, :in_parent)
      assert decorate(doc, parent_def.range) =~ "«@in_parent true»"

      assert child_def.type == :module_attribute
      assert child_def.subtype == :definition
      assert child_def.subject == Subject.module_attribute(Parent.Child, :in_child)
      assert decorate(doc, child_def.range) =~ "«@in_child true»"
    end

    test "finds references in function arguments" do
      {:ok, [_definition, reference], doc} =
        ~q[
          defmodule InArgs do
            @age 95
            def is_old?(@age), do: true
          end
        ]
        |> index()

      assert reference.type == :module_attribute
      assert reference.subtype == :reference
      assert reference.subject == Subject.module_attribute(InArgs, :age)
      assert decorate(doc, reference.range) =~ "  def is_old?(«@age»)"
    end

    test "finds references in map keys" do
      {:ok, [_, key], doc} =
        ~q[
          defmodule InMapKey do
            @foo 3
            def something(%{@foo => 3}) do
            end
          end
        ]
        |> index()

      assert key.type == :module_attribute
      assert key.subtype == :reference
      assert key.subject == Subject.module_attribute(InMapKey, :foo)
      assert decorate(doc, key.range) =~ "%{«@foo» => 3}"
    end

    test "finds references in map values" do
      {:ok, [_, value], doc} =
        ~q[
          defmodule InMapValue do
            @foo 3
            def something(%{foo: @foo}) do
            end
          end
        ]
        |> index()

      assert value.type == :module_attribute
      assert value.subtype == :reference
      assert value.subject == Subject.module_attribute(InMapValue, :foo)
      assert decorate(doc, value.range) =~ "%{foo: «@foo»}"
    end
  end
end
