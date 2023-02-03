defmodule Lexical.SourceFile.ConversionsTest do
  alias Lexical.SourceFile.Conversions
  alias Lexical.SourceFile.Position, as: ExPosition
  alias Lexical.SourceFile

  use ExUnit.Case

  defp lsp_position(line, char) do
    %{line: line, character: char}
  end

  defp doc(text) do
    SourceFile.new("file:///file.ex", text, 0)
  end

  describe "to_elixir/2 for positions" do
    test "empty" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 0), doc(""))
      assert %ExPosition{line: 0, character: 0} = pos
    end

    test "single first char" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 0), doc("abcde"))
      assert %ExPosition{line: 0, character: 0} == pos
    end

    test "single line" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 0), doc("abcde"))
      assert %ExPosition{line: 0, character: 0} == pos
    end

    test "single line utf8" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 6), doc("🏳️‍🌈abcde"))
      assert %ExPosition{line: 0, character: 14} == pos
    end

    test "multi line" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(1, 1), doc("abcde\n1234"))
      assert %ExPosition{line: 1, character: 1} == pos
    end

    # LSP spec 3.17 https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#position
    # position character If the character value is greater than the line length it defaults back to the line length

    test "position > line length of an empty document" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 15), doc(""))
      assert %ExPosition{line: 0, character: 0} == pos
    end

    test "position > line length of a document with characters" do
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(0, 15), doc("abcde"))
      assert %ExPosition{line: 0, character: 5} == pos
    end

    #   # This is not specified in LSP but some clients fail to synchronize text properly
    test "position > line length multi line after last line" do
      # the behavior that conversions does is to clamp at the start line of the end of the
      # document.
      assert {:ok, pos} = Conversions.to_elixir(lsp_position(8, 2), doc("abcde\n1234"))
      assert %ExPosition{line: 2, character: 0} == pos
    end
  end
end
