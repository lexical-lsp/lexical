defmodule Lexical.Server.CodeIntelligence.Definition do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range
  alias Lexical.Text

  require Logger

  def definition(%Project{} = project, %SourceFile{} = source_file, %Position{} = position) do
    maybe_location = RemoteControl.Api.definition(project, source_file, position)
    parse_location(maybe_location, source_file)
  end

  defp parse_location(%ElixirSense.Location{} = location, source_file) do
    %{file: file, line: line, column: column} = location
    file_path = file || source_file.path
    uri = SourceFile.Path.ensure_uri(file_path)

    with {:ok, source_file} <- SourceFile.Store.open_temporary(uri),
         {:ok, text} <- SourceFile.fetch_text_at(source_file, line) do
      {:ok, {source_file, to_precise_range(text, line, column)}}
    else
      _ ->
        {:error, "Could not open source file or fetch line text: #{inspect(file_path)}"}
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp to_precise_range(text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        to_range(start_pos, end_pos)

      _ ->
        # If the column is 1, but the code doesn't start on the first column, which isn't what we want.
        # The cursor will be placed to the left of the actual definition.
        column = if column == 1, do: Text.count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        to_range(pos, pos)
    end
  end

  defp to_range({begin_line, begin_column}, {end_line, end_column}) do
    Range.new(
      Position.new(begin_line, begin_column),
      Position.new(end_line, end_column)
    )
  end
end
