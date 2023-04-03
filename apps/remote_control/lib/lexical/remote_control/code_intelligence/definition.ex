defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range

  require Logger

  def definition(%SourceFile{} = source_file, %Position{} = position) do
    maybe_location =
      source_file
      |> SourceFile.to_string()
      |> ElixirSense.definition(position.line + 1, position.character + 1)

    if maybe_location do
      %{file: file, line: line, column: column} = maybe_location
      file_path = file || source_file.path

      with {:ok, {source_file, range}} <- location_to_range(file_path, line, column) do
        {:ok, %{source_file: source_file, range: range}}
      end
    else
      {:ok, nil}
    end
  end

  defp location_to_range(file_path, line, column) do
    uri = SourceFile.Path.ensure_uri(file_path)

    with {:ok, source_file} <- SourceFile.Store.open_temporary(uri),
         {:ok, {:line, text, _, _, _}} = SourceFile.fetch_line_at(source_file, line - 1) do
      {:ok, {source_file, to_persisted_range(text, line, column)}}
    else
      _ ->
        {:error, "Could not open source file: #{inspect(file_path)}"}
    end
  end

  defp to_persisted_range(text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: begin, end: end_} ->
        {begin_line, begin_column} = begin
        {end_line, end_column} = end_
        to_range({begin_line, begin_column}, {end_line, end_column})

      _ ->
        # NOTE: sometimes the column is 1, the cursor looks strange
        # so we need to normalize it to the first char column
        column = if column == 1, do: first_char_column(text), else: column
        to_range({line, column}, {line, column})
    end
  end

  defp to_range(begin, end_) do
    {begin_line, begin_column} = begin
    {end_line, end_column} = end_

    %Range{
      start: %Position{line: begin_line - 1, character: begin_column - 1},
      end: %Position{line: end_line - 1, character: end_column - 1}
    }
  end

  defp first_char_column(string) do
    original_length = String.length(string)
    trimmed_length = String.length(String.trim_leading(string))
    original_length - trimmed_length + 1
  end
end
