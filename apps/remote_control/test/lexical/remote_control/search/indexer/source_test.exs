defmodule Lexical.RemoteControl.Search.Indexer.SourceTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.Test.RangeSupport

  import Lexical.Test.CodeSigil
  import RangeSupport

  use ExUnit.Case

  def index(source, filter \\ &Function.identity/1) do
    path = "/foo/bar/baz.ex"
    doc = Document.new("file:///#{path}", source, 1)

    case Indexer.Source.index("/foo/bar/baz.ex", source) do
      {:ok, indexed_items} ->
        indexed_items = Enum.filter(indexed_items, filter)
        {:ok, indexed_items, doc}

      error ->
        error
    end
  end

  def index_modules(source) do
    index(source, &(&1.type == :module))
  end

  def index_functions(source) do
    index(source, fn entry ->
      entry.type in [:public_function, :private_function] and entry.subtype == :definition
    end)
  end

  def index_function_references(source) do
    index(source, fn entry ->
      entry.type in [:function] and entry.subtype == :reference
    end)
  end

  describe "indexing function references" do
    test "calling a zero-arg remote function with parens" do
      code = ~q[
        defmodule Remote do
          def something do
            OtherModule.test()
          end
        end
      ]x

      {:ok, [test], _} = index_function_references(code)
      assert "OtherModule.test()" = extract(code, test.range)
    end
  end

  test "calling a zero-arg remote function without parens" do
    code = ~q[
        defmodule Remote do
          def something do
            OtherModule.test
          end
        end
      ]

    {:ok, [test | _], _} = index_function_references(code)

    assert "OtherModule.test" = extract(code, test.range)
  end

  test "calling a one-arg remote function" do
    code = ~q[
        defmodule Remote do
          def something do
            OtherModule.test(:arg)
          end
        end
      ]

    {:ok, [test], _} = index_function_references(code)
    assert "OtherModule.test(:arg)" = extract(code, test.range)
  end

  test "calling a remote function that spans multiple lines" do
    code = ~q[
        defmodule Remote do
          def something do
            OtherModule.test(
              :first,
              :second,
              :third
            )
          end
        end
    ]
    flunk()
  end
end
