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

      assert completion.insert_text == "dedup()"
    end

    test "arity > 1 omits the first argument if in a pipeline", %{project: project} do
      {:ok, completion} =
        project
        |> complete("|> Enum.chunk_b|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "chunk_by(${1:fun})"
    end

    test "do not add parens if they're already present", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Enum.dedup_b|()")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "dedup_by"
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

      arity_one_completions =
        Enum.filter(completions, fn completion ->
          String.ends_with?(completion.sort_text, "/1") and completion.detail == "(Capture)"
        end)

      assert length(arity_one_completions) > 0

      Enum.each(arity_one_completions, fn completion ->
        assert String.ends_with?(completion.insert_text, "/1")
      end)
    end

    test "of arity 1 are suggested with named params", %{project: project} do
      source = ~q[
        Enum.map(1..10, &Integer.to_|)
      ]

      completions = complete(project, source)

      arity_one_completions =
        Enum.filter(completions, fn completion ->
          String.ends_with?(completion.sort_text, "/1") and
            completion.detail =~ "(Capture with"
        end)

      assert length(arity_one_completions) > 0

      Enum.each(arity_one_completions, fn completion ->
        assert String.contains?(completion.insert_text, "(${1:")
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
               "reduce_while(${1:enumerable}, ${2:acc}, ${3:fun})"
    end

    test "work with Kernel arity one functions", %{project: project} do
      source = ~q[
        &is_ma|
      ]

      [capture, args_capture] =
        project
        |> complete(source)
        |> Enum.filter(&(&1.sort_text == "&is_map/1"))

      assert capture.detail == "(Capture)"
      assert capture.insert_text == "is_map/1"

      assert args_capture.detail == "(Capture with arguments)"
      assert args_capture.insert_text_format == :snippet
      assert args_capture.insert_text == "is_map(${1:term})"
    end

    test "work with kernel two arity functions", %{project: project} do
      [is_map_key_complete, is_map_key_args] = complete(project, "&is_map_key|")

      assert is_map_key_complete.insert_text == "is_map_key/2"
      assert is_map_key_complete.detail == "(Capture)"

      assert is_map_key_args.insert_text == "is_map_key(${1:map}, ${2:key})"
      assert is_map_key_args.detail == "(Capture with arguments)"
      assert is_map_key_args.insert_text_format == :snippet
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
