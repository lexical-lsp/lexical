defmodule Lexical.Test.PositionSupport do
  alias Lexical.Document.Position
  alias Lexical.Document.Line
  alias Lexical.Document.Lines

  import Line

  @doc """
  Builds a position containing a stub line.
  """
  def position(line, character) do
    stub_line = line(text: "", ending: "\n", line_number: line, ascii?: true)

    lines =
      line
      |> empty_lines()
      |> put_in([Access.key(:lines), Access.elem(line - 1)], stub_line)

    Position.new(lines, line, character)
  end

  defp empty_lines(length) do
    tuple = List.to_tuple(for(x <- 1..length, do: x))
    %Lines{lines: tuple, starting_index: 1}
  end
end
