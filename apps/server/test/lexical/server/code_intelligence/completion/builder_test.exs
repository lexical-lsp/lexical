defmodule Lexical.Server.CodeIntelligence.Completion.BuilderTest do
  alias Lexical.Ast
  alias Lexical.Ast.Env
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.Server.CodeIntelligence.Completion.SortScope

  use ExUnit.Case, async: true

  import Lexical.Server.CodeIntelligence.Completion.Builder
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
    test "scope order follows module -> variable -> local -> remote -> global -> auto -> default" do
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

  describe "snippet edge cases" do
    # The following would crash due to missing case clauses
    # in `prefix_length/1`
    test "handles aliases inside locals" do
      "before __MODULE__.Submodule|"
      |> new_env()
      |> snippet("", label: "")
    end

    test "handles locals inside a module attribute" do
      "@hello.Submodule"
      |> new_env()
      |> snippet("", label: "")
    end
  end
end
