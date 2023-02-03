defmodule Lexical.SourceFile.Conversions do
  @moduledoc """
  Functions to convert between language server representations and elixir-native representations.

  The LSP protocol defines positions in terms of their utf-16 representation (thanks, windows),
  so when a document change comes in, we need to recalculate the positions of the change if
  the line contains non-ascii characters. If it's a pure ascii line, then the positions
  are the same in both utf-8 and utf-16, since they reference characters and not bytes.
  """
  alias Lexical.CodeUnit
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Line
  alias Lexical.SourceFile.Document
  alias Lexical.SourceFile.Range
  alias Lexical.SourceFile.Position

  import Line

  def ensure_uri("file://" <> _ = uri), do: uri

  def ensure_uri(path),
    do: Lexical.SourceFile.Path.to_uri(path)

  def ensure_path("file://" <> _ = uri),
    do: Lexical.SourceFile.Path.from_uri(uri)

  def ensure_path(path), do: path

  def to_elixir(%Range{} = range, _) do
    {:ok, range}
  end

  def to_elixir(%Position{} = position, _) do
    {:ok, position}
  end

  def to_elixir(%{start: _, end: _} = ls_range, %SourceFile{} = source) do
    with {:ok, start_pos} <- to_elixir(ls_range.start, source.document),
         {:ok, end_pos} <- to_elixir(ls_range.end, source.document) do
      {:ok, %Range{start: start_pos, end: end_pos}}
    end
  end

  def to_elixir(%{line: _, character: _} = position, %SourceFile{} = source_file) do
    to_elixir(position, source_file.document)
  end

  def to_elixir(%{line: _, character: _} = position, %Document{} = document) do
    document_size = Document.size(document)
    # we need to handle out of bounds line numbers, because it's possible to build a document
    # by starting with an empty document and appending to the beginning of it, with a start range of
    # {0, 0} and and end range of {1, 0} (replace the first line)
    document_line_number = min(position.line, document_size)
    elixir_line_number = document_line_number + document.starting_index
    ls_character = position.character

    cond do
      document_line_number == document_size and ls_character == 0 ->
        # allow a line one more than the document size, as long as the character is 0.
        # that means we're operating on the last line of the document
        {:ok, Position.new(elixir_line_number, ls_character)}

      position.line >= document_size ->
        # they've specified something outside of the document clamp it down so they can append at the
        # end
        {:ok, Position.new(elixir_line_number, 0)}

      true ->
        with {:ok, line} <- Document.fetch_line(document, elixir_line_number),
             {:ok, elixir_character} <- extract_elixir_character(position, line) do
          {:ok, Position.new(elixir_line_number, elixir_character)}
        end
    end
  end

  def to_elixir(%{range: %{start: start_pos, end: end_pos}}, _source_file) do
    # this is actually an elixir sense range... note that it's a bare map with
    # column keys rather than character keys.
    %{line: start_line, column: start_col} = start_pos
    %{line: end_line, column: end_col} = end_pos

    range = %Range{
      start: Position.new(start_line, start_col - 1),
      end: Position.new(end_line, end_col - 1)
    }

    {:ok, range}
  end

  # Private

  defp extract_elixir_character(
         %{line: _, character: _} = position,
         line(ascii?: true, text: text)
       ) do
    character = min(position.character, byte_size(text))
    {:ok, character}
  end

  defp extract_elixir_character(%{line: _, character: _} = position, line(text: utf8_text)) do
    with {:ok, code_unit} <- CodeUnit.to_utf8(utf8_text, position.character) do
      character = min(code_unit, byte_size(utf8_text))
      {:ok, character}
    end
  end
end
