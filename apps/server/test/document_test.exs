defmodule Lexical.DocumentTest do
  alias Lexical.Document
  alias Lexical.Protocol.Types.Position
  alias Lexical.Protocol.Types.Range
  alias Lexical.Protocol.Types.TextEdit

  use ExUnit.Case
  use ExUnitProperties

  import Lexical.Document, except: [to_string: 1]

  def text(%Lexical.Document{} = source) do
    Document.to_string(source)
  end

  def with_a_simple_module(_) do
    module = """
    defmodule MyModule do
      def foo, do: 3

      def bar(a, b) do
        a + b
      end
    end
    """

    {:ok, module: module}
  end

  def file_uri do
    "file:///elixir.ex"
  end

  def edit(text) do
    TextEdit.new(new_text: text, range: nil)
  end

  def edit(text, range) do
    TextEdit.new(new_text: text, range: range)
  end

  describe "new" do
    setup [:with_a_simple_module]

    test "it should be able to parse a single line" do
      assert parsed = new(file_uri(), "hello", 1)

      assert {:ok, "hello"} = fetch_text_at(parsed, 1)
    end

    test "it should parse its input into lines", ctx do
      assert parsed = new(file_uri(), ctx.module, 100)
      refute parsed.dirty?
      assert parsed.version == 100

      assert {:ok, "defmodule MyModule do"} = fetch_text_at(parsed, 1)
      assert {:ok, "  def foo, do: 3"} = fetch_text_at(parsed, 2)
      assert {:ok, ""} = fetch_text_at(parsed, 3)
      assert {:ok, "  def bar(a, b) do"} = fetch_text_at(parsed, 4)
      assert {:ok, "    a + b"} = fetch_text_at(parsed, 5)
      assert {:ok, "  end"} = fetch_text_at(parsed, 6)
      assert {:ok, "end"} = fetch_text_at(parsed, 7)

      assert :error = fetch_text_at(parsed, 8)
    end
  end

  describe "apply_content_changes" do
    # tests and helper functions ported from https://github.com/microsoft/vscode-languageserver-node
    # note thet those functions are not production quality e.g. they don't deal with utf8/utf16 encoding issues
    defp index_of(string, substring) do
      case String.split(string, substring, parts: 2) do
        [left, _] -> left |> String.codepoints() |> length
        [_] -> -1
      end
    end

    def get_line_offsets(text) do
      text
      |> String.codepoints()
      |> do_line_offset(1, 0, [{0, 0}])
    end

    def do_line_offset([], _current_line, _current_index, offsets) do
      Map.new(offsets)
    end

    def do_line_offset(["\r", "\n" | rest], current_line, current_index, offsets) do
      do_line_offset(rest, current_line + 1, current_index + 2, [
        {current_line, current_index + 2} | offsets
      ])
    end

    def do_line_offset(["\n" | rest], current_line, current_index, offsets) do
      do_line_offset(rest, current_line + 1, current_index + 1, [
        {current_line, current_index + 1} | offsets
      ])
    end

    def do_line_offset(["\r" | rest], current_line, current_index, offsets) do
      do_line_offset(rest, current_line + 1, current_index + 1, [
        {current_line, current_index + 1} | offsets
      ])
    end

    def do_line_offset([_c | rest], current_line, current_index, offsets) do
      do_line_offset(rest, current_line, current_index + 1, offsets)
    end

    defp find_low_high(low, high, offset, line_offsets) when low < high do
      mid = floor((low + high) / 2)

      if line_offsets[mid] > offset do
        find_low_high(low, mid, offset, line_offsets)
      else
        find_low_high(mid + 1, high, offset, line_offsets)
      end
    end

    defp find_low_high(low, _high, _offset, _line_offsets), do: low

    def position_at(text, offset) do
      offset = clamp(offset, 0, text |> String.codepoints() |> length)

      line_offsets = get_line_offsets(text)
      low = 0
      high = map_size(line_offsets)

      if high == 0 do
        Position.new(line: 0, character: offset)
      else
        low = find_low_high(low, high, offset, line_offsets)

        # low is the least x for which the line offset is larger than the current offset
        # or array.length if no line offset is larger than the current offset
        line = low - 1
        Position.new(line: line, character: offset - line_offsets[line])
      end
    end

    def clamp(num, low, high) do
      num
      |> max(low)
      |> min(high)
    end

    def new_position(l, c) do
      Position.new(line: l, character: c)
    end

    def position_after_substring(text, sub_text) do
      index = index_of(text, sub_text)
      position_at(text, index + (String.to_charlist(sub_text) |> length))
    end

    def range_for_substring(source, sub_text) do
      index = index_of(source, sub_text)

      substring_len =
        sub_text
        |> String.to_charlist()
        |> length()

      Range.new(
        start: position_at(source, index),
        end: position_at(source, index + substring_len)
      )
    end

    def range_after_substring(source_text, sub_text) do
      pos = position_after_substring(source_text, sub_text)
      Range.new(start: pos, end: pos)
    end

    def new_range(sl, sc, el, ec) do
      Range.new(start: new_position(sl, sc), end: new_position(el, ec))
    end

    def run_changes(original, changes, opts \\ []) do
      final_version = Keyword.get(opts, :version, 1)
      source_file = new(file_uri(), original, 0)
      apply_content_changes(source_file, final_version, changes)
    end

    test "empty update" do
      assert {:ok, source} = run_changes("abc123", [], version: 1)
      assert "abc123" == text(source)
      assert source.version == 0
    end

    test "setting the version" do
      assert {:ok, source} = run_changes("abc123", [edit("mornin")], version: 3)
      assert "mornin" == text(source)
      assert source.version == 3
    end

    test "full update" do
      assert {:ok, source} = run_changes("abc123", [edit("efg456")])
      assert "efg456" == text(source)
      assert source.version == 1

      assert {:ok, source} =
               run_changes(
                 "abc123",
                 [
                   edit("hello"),
                   edit("world")
                 ],
                 version: 2
               )

      assert "world" == text(source)
      assert 2 = source.version
    end

    test "starting a document" do
      assert {:ok, source} =
               run_changes("", [
                 edit("document", new_range(0, 0, 1, 0))
               ])

      assert "document" = text(source)
    end

    test "incrementally removing content" do
      hello_world = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(hello_world, [
                 edit("", range_for_substring(hello_world, "hello, world!"))
               ])

      assert "function abc() {\n  console.log(\"\");\n}" = text(source)
    end

    test "incrementally removing multi-line content" do
      orig = "function abc() {\n  foo();\n  bar();\n  \n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("", range_for_substring(orig, "  foo();\n  bar();\n"))
               ])

      assert "function abc() {\n  \n}" = text(source)
    end

    test "incrementally removing multi-line content 2" do
      orig = "function abc() {\n  foo();\n  bar();\n  \n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("", range_for_substring(orig, "foo();\n  bar();"))
               ])

      assert "function abc() {\n  \n  \n}" == text(source)
    end

    test "incrementally adding content" do
      orig = "function abc() {\n  console.log(\"hello\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit(", world!", range_after_substring(orig, "hello"))
               ])

      assert "function abc() {\n  console.log(\"hello, world!\");\n}" == text(source)
    end

    test "incrementally adding multi-line content" do
      orig = "function abc() {\n  while (true) {\n    foo();\n  };\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("\n    bar();", range_after_substring(orig, "foo();"))
               ])

      assert "function abc() {\n  while (true) {\n    foo();\n    bar();\n  };\n}" == text(source)
    end

    test "incrementally replacing single-line content, more chars" do
      orig = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("hello, test case!!!", range_for_substring(orig, "hello, world!"))
               ])

      assert "function abc() {\n  console.log(\"hello, test case!!!\");\n}" == text(source)
    end

    test "incrementally replacing single-line content, less chars" do
      orig = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("hey", range_for_substring(orig, "hello, world!"))
               ])

      assert "function abc() {\n  console.log(\"hey\");\n}" == text(source)
    end

    test "incrementally replacing single-line content, same num of chars" do
      orig = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("world, hello!", range_for_substring(orig, "hello, world!"))
               ])

      assert "function abc() {\n  console.log(\"world, hello!\");\n}" == text(source)
    end

    test "incrementally replacing multi-line content, more lines" do
      orig = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("\n//hello\nfunction d(){", range_for_substring(orig, "function abc() {"))
               ])

      assert "\n//hello\nfunction d(){\n  console.log(\"hello, world!\");\n}" == text(source)
    end

    test "incrementally replacing multi-line content, fewer lines" do
      orig = "a1\nb1\na2\nb2\na3\nb3\na4\nb4\n"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("xx\nyy", range_for_substring(orig, "\na3\nb3\na4\nb4\n"))
               ])

      assert "a1\nb1\na2\nb2xx\nyy" == text(source)
    end

    test "incrementally replacing multi-line content, same num of lines and chars" do
      orig = "a1\nb1\na2\nb2\na3\nb3\na4\nb4\n"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("\nxx1\nxx2", range_for_substring(orig, "a2\nb2\na3"))
               ])

      assert "a1\nb1\n\nxx1\nxx2\nb3\na4\nb4\n" = text(source)
    end

    test "incrementally replacing multi-line content, same num of lines but diff chars" do
      orig = "a1\nb1\na2\nb2\na3\nb3\na4\nb4\n"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("\ny\n", range_for_substring(orig, "a2\nb2\na3"))
               ])

      assert "a1\nb1\n\ny\n\nb3\na4\nb4\n" == text(source)
    end

    test "incrementally replacing multi-line content, huge number of lines" do
      orig = "a1\ncc\nb1"
      text = for _ <- 1..20_000, into: "", do: "\ndd"

      assert {:ok, source} =
               run_changes(orig, [
                 edit(text, range_for_substring(orig, "\ncc"))
               ])

      assert "a1" <> text <> "\nb1" == text(source)
    end

    test "several incremental content changes" do
      orig = "function abc() {\n  console.log(\"hello, world!\");\n}"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("defg", new_range(0, 12, 0, 12)),
                 edit("hello, test case!!!", new_range(1, 15, 1, 28)),
                 edit("hij", new_range(0, 16, 0, 16))
               ])

      assert "function abcdefghij() {\n  console.log(\"hello, test case!!!\");\n}" = text(source)
    end

    test "basic append" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit(" some extra content", new_range(1, 3, 1, 3))
               ])

      assert "foooo\nbar some extra content\nbaz" == text(source)
    end

    test "multi-line append" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit(" some extra\ncontent", new_range(1, 3, 1, 3))
               ])

      assert "foooo\nbar some extra\ncontent\nbaz" == text(source)
    end

    test "basic delete" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("", new_range(1, 0, 1, 3))
               ])

      assert "foooo\n\nbaz" = text(source)
    end

    test "multi-line delete" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("", new_range(0, 5, 1, 3))
               ])

      assert "foooo\nbaz" == text(source)
    end

    test "single character replace" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("z", new_range(1, 2, 1, 3))
               ])

      assert "foooo\nbaz\nbaz" == text(source)
    end

    test "multi-character replace" do
      orig = "foo\nbar"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("foobar", new_range(1, 0, 1, 3))
               ])

      assert "foo\nfoobar" == text(source)
    end

    test "windows line endings are preserved in document" do
      orig = "foooo\r\nbar\rbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("z", new_range(1, 2, 1, 3))
               ])

      assert "foooo\r\nbaz\rbaz" == text(source)
    end

    test "windows line endings are preserved in inserted text" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("z\r\nz\rz", new_range(1, 2, 1, 3))
               ])

      assert "foooo\nbaz\r\nz\rz\nbaz" == text(source)
    end

    test "utf8 glyphs are preserved in document" do
      orig = "foooo\nb🏳️‍🌈r\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("z", new_range(1, 7, 1, 8))
               ])

      assert "foooo\nb🏳️‍🌈z\nbaz" == text(source)
    end

    test "utf8 glyphs are preserved in inserted text" do
      orig = "foooo\nbar\nbaz"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("z🏳️‍🌈z", new_range(1, 2, 1, 3))
               ])

      assert "foooo\nbaz🏳️‍🌈z\nbaz" == text(source)
    end

    test "works with a content change event" do
      orig = """
      defmodule LanguageServer.Experimental.Server.Test do
        def foo do
          {"🎸",    "other"}
        end
      end
      """

      event =
        edit(
          "",
          Range.new(
            start: Position.new(character: 0, line: 2),
            end: Position.new(character: 22, line: 2)
          )
        )

      assert {:ok, source} = run_changes(orig, [event])
      assert {:ok, ""} = fetch_text_at(source, 3)
    end

    test "deleting a line with a multi-byte character" do
      orig = """
      defmodule LanguageServer.Experimental.Server.Test do
        def foo do
          {"🎸", "other"}
        end
      end
      """

      assert {:ok, source} =
               run_changes(orig, [
                 edit("", new_range(2, 0, 2, 19))
               ])

      {:ok, line} = fetch_text_at(source, 3)
      assert line == ""
    end

    test "inserting a line with unicode" do
      orig = """
      defmodule MyModule do
        def func do

        end
      end
      """

      assert {:ok, source} =
               run_changes(orig, [
                 edit(~s(    {"🎸",   "ok"}), new_range(2, 0, 2, 0)),
                 edit("", new_range(2, 11, 2, 13))
               ])

      {:ok, line} = fetch_text_at(source, 3)

      assert line == "    {\"🎸\", \"ok\"}"
    end

    test "invalid update range - before the document starts -> before the document starts" do
      orig = "foo\nbar"
      invalid_range = new_range(-2, 0, -1, 3)

      assert {:error, {:invalid_range, ^invalid_range}} =
               run_changes(orig, [
                 edit("abc123", new_range(-2, 0, -1, 3))
               ])
    end

    test "invalid update range - before the document starts -> the middle of document" do
      orig = "foo\nbar"
      invalid_range = new_range(-1, 0, 0, 3)

      assert {:error, {:invalid_range, ^invalid_range}} =
               run_changes(orig, [
                 edit("foobar", new_range(-1, 0, 0, 3))
               ])
    end

    test "invalid update range - the middle of document -> after the document ends" do
      orig = "foo\nbar"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("foobar", new_range(1, 0, 1, 10))
               ])

      assert "foo\nfoobar" == text(source)
    end

    test "invalid update range - after the document ends -> after the document ends" do
      orig = "foo\nbar"

      assert {:ok, source} =
               run_changes(orig, [
                 edit("abc123", new_range(3, 0, 6, 10))
               ])

      assert "foo\nbarabc123" == text(source)
    end

    test "invalid update range - before the document starts -> after the document ends" do
      orig = "foo\nbar"
      invalid_range = new_range(-1, 1, 2, 10_000)

      assert {:error, {:invalid_range, ^invalid_range}} =
               run_changes(orig, [
                 edit("entirely new content", invalid_range)
               ])
    end
  end
end
