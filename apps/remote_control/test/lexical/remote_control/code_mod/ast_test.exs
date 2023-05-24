defmodule Lexical.RemoteControl.CodeMod.AstTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeMod.Ast
  alias Sourceror.Zipper

  use Lexical.Test.CodeMod.Case, enable_ast_conversion: false

  setup do
    text = ~q[
      line = 1
      line = 2
      line = 3
      line = 4
      ""
    ]t

    document = doc(text)
    {:ok, document: document}
  end

  def apply_code_mod({:ok, zipper}, _ast, _opts) do
    {ast, _} = Zipper.top(zipper)
    Sourceror.to_string(ast)
  end

  def apply_code_mod({:ok, zipper, acc}, ast, opts) do
    converted = apply_code_mod({:ok, zipper}, ast, opts)
    {converted, acc}
  end

  def doc(string) do
    Document.new("file:///file.ex", string, 1)
  end

  def range(start_line, start_column, end_line, end_column) do
    Document.Range.new(
      Document.Position.new(start_line, start_column),
      Document.Position.new(end_line, end_column)
    )
  end

  defp underscore_variable({{var_name, meta, nil}, mod}) do
    {{:"_#{var_name}", meta, nil}, mod}
  end

  defp underscore_variable(zipper), do: zipper

  defp underscore_variable({{var_name, meta, nil}, mod}, acc) do
    {{{:"_#{var_name}", meta, nil}, mod}, acc + 1}
  end

  defp underscore_variable(zipper, acc), do: {zipper, acc}

  describe "traverse_line" do
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
