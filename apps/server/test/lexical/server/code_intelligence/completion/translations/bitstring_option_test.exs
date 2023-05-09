defmodule Lexical.Server.CodeIntelligence.Completion.Translations.BitstringOptionsTest do
  use Lexical.Test.Server.CompletionCase

  describe "bitstring options" do
    test "offers completions after ::", %{project: project} do
      assert {:ok, completions} =
               project
               |> complete("<<x::|")
               |> fetch_completion(kind: :unit)

      for completion <- completions do
        assert String.starts_with?(completion.insert_text, "x::")
      end
    end

    test "offers completions after :: in an existing context", %{project: project} do
      assert {:ok, completions} =
               project
               |> complete("<<foo::u32, x::|")
               |> fetch_completion(kind: :unit)

      for completion <- completions do
        assert String.starts_with?(completion.insert_text, "x::")
      end
    end

    test "supports integer", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("<<x::inte|")
               |> fetch_completion(kind: :unit)

      assert completion.insert_text == "x::integer"
    end

    test "doesn't get confused if the completion is 'in'", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("<<x::in|")
               |> fetch_completion(kind: :unit)

      assert completion.insert_text == "x::integer"
    end

    test "supports multiple options", %{project: project} do
      assert {:ok, [utf8, utf16, utf32]} =
               project
               |> complete("<<foo::utf8, bar::ut|")
               |> fetch_completion(kind: :unit)

      assert utf8.insert_text == "bar::utf8"
      assert utf16.insert_text == "bar::utf16"
      assert utf32.insert_text == "bar::utf32"
    end

    test "supports dashed options", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("<<x::integer-siz|")
               |> fetch_completion(kind: :unit)

      assert completion.insert_text == "size"
    end

    @tag :skip
    # Note: looks like elixir sense needs a context character in order to complete
    # after a dash. Bummer.
    test "completes after a dash", %{project: project} do
      assert {:ok, completions} =
               project
               |> complete("<<x::big-integer-|")
               |> fetch_completion(kind: :unit)

      for completion <- completions do
        assert String.starts_with?(completion, "-")
      end
    end

    test "supports concatenated dashed options", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("<<x::big-integer-siz|")
               |> fetch_completion(kind: :unit)

      assert completion.insert_text == "size"
    end

    test "supports utf options", %{project: project} do
      assert {:ok, [utf8, utf16, utf32]} =
               project
               |> complete("<<foo::utf|")
               |> fetch_completion(kind: :unit)

      assert utf8.insert_text == "foo::utf8"
      assert utf16.insert_text == "foo::utf16"
      assert utf32.insert_text == "foo::utf32"
    end

    test "functions are not included", %{project: project} do
      code = ~q[
        def bin_fn() do
        end

        def other do
          <<foo::bin|
        end
      ]

      assert {:error, :not_found} =
               project
               |> complete(code)
               |> fetch_completion(kind: :function)
    end

    test "macros are not included", %{project: project} do
      code = ~q[
        def bin_fn() do
        end

        def other do
          <<foo::is_|
        end
      ]

      assert {:error, :not_found} =
               project
               |> complete(code)
               |> fetch_completion(kind: :function)
    end

    test "variables are included", %{project: project} do
      code = ~q[
      bin_length = 5
        <<foo::binary-size(bin_l|)
      ]

      assert {:ok, completion} =
               project
               |> complete(code)
               |> fetch_completion(kind: :variable)

      assert completion.insert_text == "bin_length"
    end
  end
end
