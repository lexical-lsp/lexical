defmodule Lexical.AstTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport
  alias Sourceror.Zipper

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

  describe "traverse_line" do
    setup do
      text = ~q[
      line = 1
      line = 2
      line = 3
      line = 4
      ""
    ]t

      document = Document.new("file:///file.ex", text, 1)

      {:ok, document: document}
    end

    defp underscore_variable({{var_name, meta, nil}, zipper_meta}) do
      {{:"_#{var_name}", meta, nil}, zipper_meta}
    end

    defp underscore_variable(zipper), do: zipper

    defp underscore_variable({{var_name, meta, nil}, zipper_meta}, acc) do
      {{{:"_#{var_name}", meta, nil}, zipper_meta}, acc + 1}
    end

    defp underscore_variable(zipper, acc), do: {zipper, acc}

    defp modify({:ok, zipper}) do
      {ast, _} = Zipper.top(zipper)
      Sourceror.to_string(ast)
    end

    defp modify({:ok, zipper, acc}) do
      {modify({:ok, zipper}), acc}
    end

    test "/3 should only affect the specified line", %{document: doc} do
      converted =
        doc
        |> Ast.traverse_line(2, &underscore_variable/1)
        |> modify()

      assert converted =~ "_line = 2"
      assert converted =~ "line = 1"
      assert converted =~ "line = 3"
      assert converted =~ "line = 4"
    end

    test "/4 should only affect the specified line, and keeps an accumulator", %{document: doc} do
      {converted, acc} =
        doc
        |> Ast.traverse_line(2, 0, &underscore_variable/2)
        |> modify()

      assert acc == 1
      assert converted =~ "_line = 2"
      refute converted =~ "_line = 1"
      refute converted =~ "_line = 3"
    end
  end
end
