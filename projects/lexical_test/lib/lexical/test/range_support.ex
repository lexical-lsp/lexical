defmodule Lexical.Test.RangeSupport do
  alias Lexical.Document
  alias Lexical.Document.Range
  alias Lexical.Test.CursorSupport

  import Lexical.Document.Line, only: [line: 1]

  @range_start_marker "«"
  @range_end_marker "»"

  @doc """
  Finds range markers in `text` and returns a tuple containing the range
  and the text with the markers stripped out.
  """
  @spec pop_range(text :: String.t()) :: {Range.t(), String.t()}
  def pop_range(text) do
    {start_position, text} = CursorSupport.pop_cursor(text, cursor: @range_start_marker)
    {end_position, text} = CursorSupport.pop_cursor(text, cursor: @range_end_marker)
    {Range.new(start_position, end_position), text}
  end

  def pop_all_ranges(text) do
    do_pop_all_ranges(text, [])
  end

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

  defp do_pop_all_ranges(text, ranges) do
    {start_position, text} =
      CursorSupport.pop_cursor(text, cursor: @range_start_marker, default_to_end: false)

    {end_position, text} =
      CursorSupport.pop_cursor(text, cursor: @range_end_marker, default_to_end: false)

    if start_position == nil or end_position == nil do
      {Enum.reverse(ranges), text}
    else
      do_pop_all_ranges(text, [Range.new(start_position, end_position) | ranges])
    end
  end
end
