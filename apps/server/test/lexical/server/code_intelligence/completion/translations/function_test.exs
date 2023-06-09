defmodule Lexical.Server.CodeIntelligence.Completion.Translations.FunctionTest do
  use Lexical.Test.Server.CompletionCase

  describe "function completions" do
    test "deprecated functions are marked", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.filter_map|")
               |> fetch_completion("filter_map")

      assert completion.label
      assert [:deprecated] = completion.tags
    end

    test "suggest arity 0 functions if not in a pipeline", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Application.loaded_app|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "loaded_applications()"
    end

    test "do not suggest arity 0 functions if in a pipeline", %{project: project} do
      assert {:error, :not_found} =
               project
               |> complete("|> Application.loaded_app|")
               |> fetch_completion(kind: :function)
    end

    test "arity 1 omits arguments if in a pipeline", %{project: project} do
      {:ok, [completion, _]} =
        project
        |> complete("|> Enum.dedu|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "dedup()"
      assert completion.label == "dedup()"
    end

    test "arity > 1 omits the first argument if in a pipeline", %{project: project} do
      {:ok, completion} =
        project
        |> complete("|> Enum.chunk_b|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "chunk_by(${1:fun})"
      assert completion.label == "chunk_by(fun)"
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
          String.contains?(completion.label, "/1") and completion.detail == "(Capture)"
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
          not String.contains?(completion.label, ",") and
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
        |> Enum.filter(fn completion ->
          sort_text = completion.sort_text
          # arity 1 and is is_map
          not String.contains?(sort_text, ",") and
            not String.contains?(sort_text, "/2") and
            String.contains?(sort_text, "is_map")
        end)

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

  describe "handling default arguments" do
    test "works with a first arg", %{project: project} do
      {:ok, [arity_1, arity_2]} =
        project
        |> complete("Project.DefaultArgs.first|")
        |> fetch_completion(kind: :function)

      assert arity_1.insert_text == "first_arg(${1:y})"
      assert arity_2.insert_text == "first_arg(${1:x}, ${2:y})"
    end

    test "works with the middle arg", %{project: project} do
      {:ok, [arity_1, arity_2]} =
        project
        |> complete("Project.DefaultArgs.middle|")
        |> fetch_completion(kind: :function)

      assert arity_1.insert_text == "middle_arg(${1:a}, ${2:c})"
      assert arity_2.insert_text == "middle_arg(${1:a}, ${2:b}, ${3:c})"
    end

    test "works with the last arg", %{project: project} do
      {:ok, [arity_1, arity_2]} =
        project
        |> complete("Project.DefaultArgs.last|")
        |> fetch_completion(kind: :function)

      assert arity_1.insert_text == "last_arg(${1:x})"
      assert arity_2.insert_text == "last_arg(${1:x}, ${2:y})"
    end

    test "works with options", %{project: project} do
      {:ok, [arity_1, arity_2]} =
        project
        |> complete("Project.DefaultArgs.opt|")
        |> fetch_completion(kind: :function)

      assert arity_1.insert_text == "options(${1:a})"
      assert arity_2.insert_text == "options(${1:a}, ${2:opts})"
    end

    test "works with struct defaults", %{project: project} do
      {:ok, [arity_1, arity_2]} =
        project
        |> complete("Project.DefaultArgs.struct|")
        |> fetch_completion(kind: :function)

      assert arity_1.insert_text == "struct_arg(${1:a})"
      assert arity_2.insert_text == "struct_arg(${1:a}, ${2:b})"
    end

    test "works with pattern match args", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Project.DefaultArgs.pattern_match|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "pattern_match_arg(${1:user})"
    end

    test "works with reverse pattern match args", %{project: project} do
      {:ok, completion} =
        project
        |> complete("Project.DefaultArgs.reverse|")
        |> fetch_completion(kind: :function)

      assert completion.insert_text == "reverse_pattern_match_arg(${1:user})"
    end
  end

  describe "ordering" do
    test "dunder functions aren't boosted", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.|")
               |> fetch_completion("__info__")

      refute boosted?(completion)
    end

    test "dunder and default functions have lower completion priority", %{project: project} do
      completions = complete(project, "GenServer.|")

      defaults = ["module_info(", "behaviour_info("]

      low_priority_completion? = fn fun ->
        String.starts_with?(fun.label, "__") or
          Enum.any?(defaults, &String.contains?(fun.sort_text, &1))
      end

      {low_priority_completions, normal_completions} =
        Enum.split_with(completions, low_priority_completion?)

      for completion <- low_priority_completions do
        refute boosted?(completion)
      end

      for completion <- normal_completions do
        assert boosted?(completion)
      end
    end
  end
end
