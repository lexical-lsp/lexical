defmodule Lexical.AstTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport
  alias Sourceror.Zipper

  import CursorSupport
  import CodeSigil
  import Lexical.Test.PositionSupport

  use ExUnit.Case, async: true

  describe "cursor_path/2" do
    defp cursor_path(text) do
      {position, document} = pop_cursor(text, as: :document)
      Ast.cursor_path(document, position)
    end

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
      assert path == [{:__cursor__, [closing: [line: 1, column: 12], line: 1, column: 1], []}]
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

    defp underscore_variable(%Zipper{node: {var_name, meta, nil}} = zipper) do
      Zipper.replace(zipper, {:"_#{var_name}", meta, nil})
    end

    defp underscore_variable(zipper), do: zipper

    defp underscore_variable(%Zipper{node: {_var_name, _meta, nil}} = zipper, acc) do
      zipper = underscore_variable(zipper)
      {zipper, acc + 1}
    end

    defp underscore_variable(zipper, acc), do: {zipper, acc}

    defp modify({:ok, zipper}) do
      %Zipper{node: ast} = Zipper.top(zipper)
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

  describe "contains_position?/2 single line node" do
    setup do
      [single_line_ast] = ast(~q|
        [
          single_line_call(1, 2, 3),
        ]
      |)

      range = {{2, 3}, {2, 27}}

      {:ok, [ast: single_line_ast, range: range]}
    end

    test "at the bounds", %{ast: ast, range: range} do
      {{start_line, start_col}, {end_line, end_col}} = range

      assert Ast.contains_position?(ast, position(start_line, start_col))
      assert Ast.contains_position?(ast, position(end_line, end_col))
    end

    test "within the node", %{ast: ast, range: range} do
      {{start_line, start_col}, _} = range

      assert Ast.contains_position?(ast, position(start_line, start_col + 1))
    end

    test "outside the bounds", %{ast: ast, range: range} do
      {{start_line, start_col}, {end_line, end_col}} = range

      refute Ast.contains_position?(ast, position(start_line, start_col - 1))
      refute Ast.contains_position?(ast, position(start_line - 1, start_col))
      refute Ast.contains_position?(ast, position(end_line, end_col + 1))
      refute Ast.contains_position?(ast, position(end_line + 1, end_col))
    end
  end

  describe "contains_position?/2 multi line node" do
    setup do
      [three_line_ast] = ast(~q|
        [
          multi_line_call(
            1, 2, 3
          )
        ]
      |)

      range = {{2, 3}, {4, 3}}

      {:ok, [ast: three_line_ast, range: range]}
    end

    test "at the bounds", %{ast: ast, range: range} do
      {{start_line, start_col}, {end_line, end_col}} = range

      assert Ast.contains_position?(ast, position(start_line, start_col))
      assert Ast.contains_position?(ast, position(end_line, end_col))
    end

    test "on the first line", %{ast: ast, range: range} do
      {{start_line, start_col}, _} = range

      assert Ast.contains_position?(ast, position(start_line, start_col + 1))
      refute Ast.contains_position?(ast, position(start_line, start_col - 1))
    end

    test "on the last line", %{ast: ast, range: range} do
      {_, {end_line, end_col}} = range

      assert Ast.contains_position?(ast, position(end_line, end_col - 1))
      refute Ast.contains_position?(ast, position(end_line, end_col + 1))
    end

    test "within the lines", %{ast: ast, range: range} do
      {{start_line, _}, _} = range

      assert Ast.contains_position?(ast, position(start_line + 1, 1))
      assert Ast.contains_position?(ast, position(start_line + 1, 1_000))
    end

    test "outside the lines", %{ast: ast, range: range} do
      {{start_line, start_col}, {end_line, end_col}} = range

      refute Ast.contains_position?(ast, position(start_line - 1, start_col))
      refute Ast.contains_position?(ast, position(end_line + 1, end_col))
    end
  end

  defp ast(s) do
    case Ast.from(s) do
      {:ok, {:__block__, _, [node]}} -> node
      {:ok, node} -> node
    end
  end
end
