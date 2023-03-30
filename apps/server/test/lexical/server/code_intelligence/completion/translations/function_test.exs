defmodule Lexical.Server.CodeIntelligence.Completion.Translations.FunctionTest do
  use Lexical.Test.Server.CompletionCase

  describe "function completions" do
    test "deprecated functions are marked", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.filter_map|")
               |> fetch_completion("filter_map")

      assert completion.detail
      assert [:deprecated] = completion.tags
    end

    test "arity 1 omits arguments if in a pipeline", %{project: project} do
      {:ok, [completion, _]} =
        project
        |> complete("|> Enum.dedu|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "dedup()$0"
    end

    test "arity > 1 omits the first argument if in a pipeline", %{project: project} do
      {:ok, completion} =
        project
        |> complete("|> Enum.chunk_b|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "chunk_by(${1:fun})$0"
    end

    test "do not add parens if they're already present", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Enum.dedup_b|()")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "dedup_by$0"
    end
  end

  describe "function captures" do
    test "suggest modules", %{project: project} do
      source = ~q[
      Enum.map(1..10, &Inte|)
      ]

      {:ok, completion} =
        project
        |> complete(source)
        |> fetch_completion(kind: :module)

      assert completion.label == "Integer"
    end

    test "of arity 1 are suggested with /1", %{project: project} do
      source = ~q[
      Enum.map(1..10, &Integer.to_|)
      ]

      completions = complete(project, source)
      arity_one_completions = Enum.filter(completions, &String.ends_with?(&1.sort_text, "/1"))

      Enum.each(arity_one_completions, fn completion ->
        assert String.ends_with?(completion.insert_text, "/1$0")
      end)
    end

    test "arity > 1 provides a snippet with parens and commas", %{project: project} do
      source = ~q[
      Enum.map(1..10, Enum.reduce_w|)
      ]

      {:ok, completion} =
        project
        |> complete(source)
        |> fetch_completion(kind: :function)

      assert completion.insert_text_format == :snippet

      assert completion.insert_text ==
               "reduce_while(${1:enumerable}, ${2:acc}, ${3:fun})$0"
    end
  end

  describe "sort_text" do
    test "dunder functions have the dunder removed in their sort_text", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.|")
               |> fetch_completion("__info__")

      assert completion.sort_text == "info/1"
    end
  end
end
