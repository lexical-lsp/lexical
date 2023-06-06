defmodule Lexical.AstTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport

  import CursorSupport
  import CodeSigil

  use ExUnit.Case, async: true

  def cursor_path(text) do
    pos = cursor_position(text)
    text = strip_cursor(text)
    doc = Document.new("file:///file.ex", text, 0)
    Ast.cursor_path(doc, pos)
  end

  describe "cursor_path/2" do
    test "contains the parent AST" do
      text = ~q[
      defmodule Foo do
        def bar do
          |
        end
      end
    ]

      path = cursor_path(text)

      assert Enum.any?(path, &match?({:def, _, _}, &1))
      assert Enum.any?(path, &match?({:defmodule, _, _}, &1))
    end

    test "returns cursor ast when is not in a container" do
      text = ~q[
      |
      defmodule Foo do
      end
      ]

      path = cursor_path(text)
      assert path == [{:__cursor__, [line: 1, column: 1], []}]
    end

    test "returns [] when can't parse the AST" do
      text = ~q[
        foo(bar do baz, bat|
      ]
      path = cursor_path(text)
      assert path == []
    end
  end
end
