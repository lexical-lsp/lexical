defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Location
  alias Lexical.Ranged
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range

  require Logger

  def handle(%GoToDefinition{} = request, _env) do
    source_file = request.source_file
    pos = request.position

    maybe_location =
      source_file
      |> SourceFile.to_string()
      |> ElixirSense.definition(pos.line + 1, pos.character + 1)

    case to_response(request.id, maybe_location, source_file) do
      {:ok, response} ->
        {:reply, response}

      {:error, reason} ->
        Logger.error("GotoDefinition conversion failed: #{inspect(reason)}")
        {:error, Responses.GotoDefinition.error(request.id, :request_failed, inspect(reason))}
    end
  end

  defp to_response(request_id, %ElixirSense.Location{} = location, %SourceFile{} = source_file) do
    %{file: file, line: line, column: column} = location

    uri = SourceFile.Path.ensure_uri(file || source_file.path)

    with {:ok, source_file} <- SourceFile.Store.open_temporary(uri),
         {:ok, {:line, text, _, _, _}} = SourceFile.fetch_line_at(source_file, line - 1),
         {:ok, range} <- to_range(text, line, column),
         {:ok, ls_range} <- Ranged.Lsp.from_native(range, source_file) do
      location = Location.new(uri: uri, range: ls_range)
      {:ok, Responses.GotoDefinition.new(request_id, location)}
    end
  end

  defp to_response(request_id, nil, _source_file) do
    {:ok, Responses.GotoDefinition.new(request_id, nil)}
  end

  defp to_range(text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: begin, end: end_} ->
        {begin_line, begin_column} = begin
        {end_line, end_column} = end_

        {:ok,
         %Range{
           start: %Position{line: begin_line - 1, character: begin_column - 1},
           end: %Position{line: end_line - 1, character: end_column - 1}
         }}

      _ ->
        column = if column == 1, do: first_char_column(text), else: column

        {:ok,
         %Range{
           start: %Position{line: line - 1, character: column - 1},
           end: %Position{line: line - 1, character: column - 1}
         }}
    end
  end

  defp first_char_column(string) do
    original_length = String.length(string)
    trimmed_length = String.length(String.trim_leading(string))
    original_length - trimmed_length + 1
  end
end
