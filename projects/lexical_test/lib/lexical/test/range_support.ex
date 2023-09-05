defmodule Lexical.Test.RangeSupport do
  alias Lexical.Document
  alias Lexical.Document.Range
  import Document.Line, only: [line: 1]

  @range_start_marker "«"
  @range_end_marker "»"

  def decorate(%Document{} = document, %Range{} = range) do
    index_range = (range.start.line - 1)..(range.end.line - 1)

    document.lines
    |> Enum.slice(index_range)
    |> Enum.map(fn line(text: text, ending: ending) -> text <> ending end)
    |> update_in([Access.at(-1)], &insert_marker(&1, @range_end_marker, range.end.character))
    |> update_in([Access.at(0)], &insert_marker(&1, @range_start_marker, range.start.character))
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  end

  def decorate(document_text, path \\ "/file.ex", %Range{} = range)
      when is_binary(document_text) do
    "file://#{path}"
    |> Document.new(document_text, 1)
    |> decorate(range)
  end

  defp insert_marker(text, marker, character) do
    {leading, trailing} = String.split_at(text, character - 1)
    leading <> marker <> trailing
  end
end
