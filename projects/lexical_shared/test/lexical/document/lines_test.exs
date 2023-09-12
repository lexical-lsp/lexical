defmodule Lexical.Document.LinesTest do
  alias Lexical.Document.Line
  alias Lexical.Document.Lines

  use ExUnit.Case, async: true
  use ExUnitProperties

  import Line

  describe "Lines Enumerable" do
    test "it should be able to be fetched by line number" do
      d = Lines.new("hello\nthere\npeople")
      assert line(text: "hello") = Enum.at(d, 0)
      assert line(text: "there") = Enum.at(d, 1)
      assert line(text: "people") = Enum.at(d, 2)
      assert nil == Enum.at(d, 3)
    end
  end

  property "always creates valid binaries" do
    check all(
            elements <-
              list_of(
                one_of([
                  string(:printable),
                  one_of([constant("\r\n"), constant("\n"), constant("\r")])
                ])
              )
          ) do
      document =
        elements
        |> IO.iodata_to_binary()
        |> Lines.new()

      for line(text: text, ending: ending) <- document do
        assert String.valid?(text)
        assert ending in ["\r\n", "\n", "\r", ""]
      end
    end
  end

  property "to_string recreates the original" do
    check all(
            elements <-
              list_of(
                one_of([
                  string(:printable),
                  one_of([constant("\r\n"), constant("\n"), constant("\r")])
                ])
              )
          ) do
      original_binary = List.to_string(elements)
      document = Lines.new(original_binary)
      assert Lines.to_string(document) == original_binary
    end
  end

  property "size reflects the original line count" do
    check all(elements <- list_of(string(:alphanumeric, min_length: 2))) do
      line_count = Enum.count(elements)
      original_binary = elements |> Enum.join("\n") |> IO.iodata_to_binary()

      document = Lines.new(original_binary)
      assert Lines.size(document) == line_count
    end
  end

  def make_line(text, line_number, ending \\ "\n") do
    line(text: text, line_number: line_number, ending: ending)
  end

  describe "sparse" do
    test "works with size/1" do
      lines = Lines.sparse([make_line("hello", 20)])
      assert Lines.size(lines) == 20
    end

    test "works with to_string/1" do
      lines =
        Lines.sparse([
          line(line_number: 2, text: "hello", ending: "\n"),
          line(line_number: 5, text: "goodbye", ending: "\n")
        ])

      expected = """

      hello


      goodbye
      """

      assert Lines.to_string(lines) == expected
    end

    test "works with fetch_line" do
      lines = Lines.sparse([make_line("first", 2), make_line("second", 4)])
      assert {:ok, line(text: "", line_number: 1)} = Lines.fetch_line(lines, 1)
      assert {:ok, line(text: "first", line_number: 2)} = Lines.fetch_line(lines, 2)
      assert {:ok, line(text: "", line_number: 3)} = Lines.fetch_line(lines, 3)
      assert {:ok, line(text: "second", line_number: 4)} = Lines.fetch_line(lines, 4)
      assert :error = Lines.fetch_line(lines, 5)
    end
  end
end
