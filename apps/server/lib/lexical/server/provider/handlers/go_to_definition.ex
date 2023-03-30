defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Location
  alias Lexical.Ranged
  alias Lexical.SourceFile
  alias Lexical.RemoteControl

  require Logger

  def handle(%GoToDefinition{} = request, env) do
    source_file = request.source_file
    pos = request.position

    maybe_location =
      RemoteControl.Api.definition(
        env.project,
        source_file,
        {pos.line + 1, pos.character + 1}
      )

    case to_response(request.id, maybe_location) do
      {:ok, response} ->
        {:reply, response}

      {:error, reason} ->
        Logger.error("GotoDefinition conversion failed: #{inspect(reason)}")
        {:error, Responses.GotoDefinition.error(request.id, :request_failed, inspect(reason))}
    end
  end

  defp to_response(request_id, nil) do
    {:ok, Responses.GotoDefinition.new(request_id, nil)}
  end

  defp to_response(request_id, location) do
    %{range: range, uri: uri} = location

    with {:ok, source_file} <- SourceFile.Store.open_temporary(uri),
         {:ok, ls_range} <- Ranged.Lsp.from_native(range, source_file) do
      location = Location.new(uri: uri, range: ls_range)
      {:ok, Responses.GotoDefinition.new(request_id, location)}
    end
  end
end
