defmodule Lexical.Server.CodeIntelligence.Completion.BuilderTest do
  alias Lexical.Ast
  alias Lexical.Ast.Env
  alias Lexical.Completion.SortScope
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem

  use ExUnit.Case, async: true

  import Lexical.Server.CodeIntelligence.Completion.Builder
  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures

  def new_env(text) do
    project = project()
    {position, document} = pop_cursor(text, as: :document)
    analysis = Ast.analyze(document)
    {:ok, env} = Env.new(project, analysis, position)
    env
  end

  def item(label, opts \\ []) do
    opts
    |> Keyword.merge(label: label)
    |> CompletionItem.new()
    |> set_sort_scope(SortScope.default())
  end

  defp sort_items(items) do
    Enum.sort_by(items, &{&1.sort_text, &1.label})
  end

  setup do
    start_supervised!(Lexical.Server.Application.document_store_child_spec())
    :ok
  end

  describe "sort scopes" do
    test "scope order follows variable -> local -> remote -> global -> auto -> default" do
      i = set_sort_scope(item("g"), SortScope.module())
      ii = set_sort_scope(item("f"), SortScope.variable())
      iii = set_sort_scope(item("e"), SortScope.local())
      iv = set_sort_scope(item("d"), SortScope.remote())
      v = set_sort_scope(item("c"), SortScope.global())
      vi = set_sort_scope(item("b"), SortScope.auto())
      vii = set_sort_scope(item("a"), SortScope.default())

      assert [^i, ^ii, ^iii, ^iv, ^v, ^vi, ^vii] = sort_items([vii, vi, v, iv, iii, ii, i])
    end

    test "low priority sorts items lower in their scope" do
      alpha_first = set_sort_scope(item("a"), SortScope.remote(false, 2))
      alpha_second = set_sort_scope(item("b"), SortScope.remote())
      alpha_third = set_sort_scope(item("c"), SortScope.remote())

      assert [^alpha_second, ^alpha_third, ^alpha_first] =
               sort_items([alpha_first, alpha_second, alpha_third])
    end

    test "deprecated items are gathered at the bottom of their scope" do
      i_deprecated = set_sort_scope(item("a"), SortScope.remote(true))
      i = set_sort_scope(item("a"), SortScope.remote())
      ii = set_sort_scope(item("b"), SortScope.remote())
      iii_low = set_sort_scope(item("c"), SortScope.remote(false, 2))

      assert [^i, ^ii, ^iii_low, ^i_deprecated] = sort_items([i_deprecated, i, ii, iii_low])
    end
  end

  describe "strip_struct_operator_for_elixir_sense/1" do
    test "with a reference followed by  __" do
      {doc, _position} =
        "%__"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "__"
    end

    test "with a reference followed by a module name" do
      {doc, _position} =
        "%Module"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Module"
    end

    test "with a reference followed by a module and a dot" do
      {doc, _position} =
        "%Module."
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Module."
    end

    test "with a reference followed by a nested module" do
      {doc, _position} =
        "%Module.Sub"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

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
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "alias Something.Else\nEl"
    end

    test "on a line with two references, replacing the first" do
      {doc, _position} =
        "%First{} = %Se"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "%First{} = Se"
    end

    test "on a line with two references, replacing the second" do
      {doc, _position} =
        "%Fir| = %Second{}"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "Fir = %Second{}"
    end

    test "with a plain module" do
      env = new_env("Module")
      {doc, _position} = strip_struct_operator_for_elixir_sense(env)

      assert doc == env.document
    end

    test "with a plain module strip_struct_reference a dot" do
      env = new_env("Module.")
      {doc, _position} = strip_struct_operator_for_elixir_sense(env)

      assert doc == env.document
    end

    test "leaves leading spaces in place" do
      {doc, _position} =
        "     %Some"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "     Some"
    end

    test "works in a function definition" do
      {doc, _position} =
        "def my_function(%Lo|)"
        |> new_env()
        |> strip_struct_operator_for_elixir_sense()

      assert doc == "def my_function(Lo)"
    end
  end
end
