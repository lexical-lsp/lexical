defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range

  require Logger

  @spec definition(SourceFile.t(), Position.t()) ::
          {:ok, {SourceFile.t(), Range.t()} | nil} | {:error, String.t()}
  def definition(%SourceFile{} = source_file, %Position{} = position) do
    maybe_location =
      source_file
      |> SourceFile.to_string()
      |> ElixirSense.definition(position.line + 1, position.character + 1)

    parse_location(maybe_location, source_file)
  end

  defp parse_location(%ElixirSense.Location{} = location, source_file) do
    %{file: file, line: line, column: column} = location
    file_path = file || source_file.path

    case location_to_range(file_path, line, column) do
      {:ok, {source_file, range}} ->
        {:ok, {source_file, range}}

      error ->
        error
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp location_to_range(file_path, line, column) do
    uri = SourceFile.Path.ensure_uri(file_path)

    with {:ok, source_file} <- SourceFile.Store.open_temporary(uri),
         {:ok, text} <- SourceFile.fetch_text_at(source_file, line - 1) do
      {:ok, {source_file, to_precise_range(text, line, column)}}
    else
      _ ->
        {:error, "Could not open source file: #{inspect(file_path)}"}
    end
  end

  defp to_precise_range(text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        to_range(start_pos, end_pos)

      _ ->
        # NOTE: sometimes the column is 1, the cursor looks strange
        # So we need to ignore the spaces before letters,
        # such as there are two spaces before `def`.
        column = if column == 1, do: count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        to_range(pos, pos)
    end
  end

  defp to_range({begin_line, begin_column}, {end_line, end_column}) do
    Range.new(
      Position.new(begin_line - 1, begin_column - 1),
      Position.new(end_line - 1, end_column - 1)
    )
  end

  defp count_leading_spaces(str), do: count_leading_spaces(str, 0)

  defp count_leading_spaces(<<c::utf8, rest::binary>>, count) when c in [?\s, ?\t],
    do: count_leading_spaces(rest, count + 1)

  defp count_leading_spaces(_, count), do: count
end
