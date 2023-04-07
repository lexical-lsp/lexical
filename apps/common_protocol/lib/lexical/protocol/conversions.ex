defmodule Lexical.Protocol.Conversions do
  @moduledoc """
  Functions to convert between language server representations and elixir-native representations.

  The LSP protocol defines positions in terms of their utf-16 representation (thanks, windows),
  so when a document change comes in, we need to recalculate the positions of the change if
  the line contains non-ascii characters. If it's a pure ascii line, then the positions
  are the same in both utf-8 and utf-16, since they reference characters and not bytes.
  """
  alias Lexical.CodeUnit
  alias Lexical.Protocol.Types.Position, as: LSPosition
  alias Lexical.Protocol.Types.Range, as: LSRange
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Document
  alias Lexical.SourceFile.Line
  alias Lexical.SourceFile.Position, as: ElixirPosition
  alias Lexical.SourceFile.Range, as: ElixirRange

  import Line

  def to_elixir(%LSRange{} = ls_range, %SourceFile{} = source) do
    with {:ok, start_pos} <- to_elixir(ls_range.start, source.document),
         {:ok, end_pos} <- to_elixir(ls_range.end, source.document) do
      {:ok, %ElixirRange{start: start_pos, end: end_pos}}
    end
  end

  def to_elixir(%LSPosition{} = position, %SourceFile{} = source_file) do
    to_elixir(position, source_file.document)
  end

  def to_elixir(%ElixirPosition{} = position, _) do
    position
  end

  def to_elixir(%LSPosition{} = position, %Document{} = document) do
    document_size = Document.size(document)
    # we need to handle out of bounds line numbers, because it's possible to build a document
    # by starting with an empty document and appending to the beginning of it, with a start range of
    # {0, 0} and and end range of {1, 0} (replace the first line)
    document_line_number = min(position.line, document_size) + document.starting_index
    ls_character = position.character

    cond do
      document_line_number == document_size and ls_character == 0 ->
        # allow a line one more than the document size, as long as the character is 0.
        # that means we're operating on the last line of the document
        {:ok, ElixirPosition.new(document_line_number, 1)}

      position.line >= document_size ->
        # they've specified something outside of the document clamp it down so they can append at the
        # end
        {:ok, ElixirPosition.new(document_line_number, 1)}

      true ->
        with {:ok, line} <- Document.fetch_line(document, document_line_number),
             {:ok, elixir_character} <- extract_elixir_character(position, line) do
          {:ok, ElixirPosition.new(document_line_number, elixir_character)}
        end
    end
  end

  def to_elixir(%{range: %{start: start_pos, end: end_pos}}, _source_file) do
    # this is actually an elixir sense range... note that it's a bare map with
    # column keys rather than character keys.
    %{line: start_line, column: start_col} = start_pos
    %{line: end_line, column: end_col} = end_pos

    range =
      ElixirRange.new(
        ElixirPosition.new(start_line, start_col),
        ElixirPosition.new(end_line, end_col)
      )

    {:ok, range}
  end

  def to_lsp(%ElixirRange{} = ex_range, %SourceFile{} = source) do
    with {:ok, start_pos} <- to_lsp(ex_range.start, source.document),
         {:ok, end_pos} <- to_lsp(ex_range.end, source.document) do
      {:ok, %LSRange{start: start_pos, end: end_pos}}
    end
  end

  def to_lsp(%ElixirPosition{} = position, %SourceFile{} = source_file) do
    to_lsp(position, source_file.document)
  end

  def to_lsp(%ElixirPosition{} = position, %Document{} = document) do
    with {:ok, line} <- Document.fetch_line(document, position.line),
         {:ok, lsp_character} <- extract_lsp_character(position, line) do
      ls_pos =
        LSPosition.new(character: lsp_character, line: position.line - document.starting_index)

      {:ok, ls_pos}
    end
  end

  def to_lsp(%LSPosition{} = position, _) do
    {:ok, position}
  end

  # Private

  defp extract_lsp_character(%ElixirPosition{} = position, line(ascii?: true, text: text)) do
    character = min(position.character - 1, byte_size(text))
    {:ok, character}
  end

  defp extract_lsp_character(%ElixirPosition{} = position, line(text: utf8_text)) do
    with {:ok, code_unit} <- CodeUnit.to_utf16(utf8_text, position.character - 1) do
      character = min(code_unit, CodeUnit.count(:utf16, utf8_text))
      {:ok, character}
    end
  end

  defp extract_elixir_character(%LSPosition{} = position, line(ascii?: true, text: text)) do
    character = min(position.character + 1, byte_size(text) + 1)
    {:ok, character}
  end

  defp extract_elixir_character(%LSPosition{} = position, line(text: utf8_text)) do
    with {:ok, code_unit} <- CodeUnit.to_utf8(utf8_text, position.character) do
      character = min(code_unit, byte_size(utf8_text) + 1)
      {:ok, character}
    end
  end
end
