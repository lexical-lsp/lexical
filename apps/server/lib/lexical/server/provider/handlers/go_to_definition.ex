defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Location
  alias Lexical.Ranged
  alias Lexical.Server.CodeIntelligence.Definition

  require Logger

  def handle(%GoToDefinition{} = request, env) do
    with {:ok, location} <-
           Definition.definition(env.project, request.source_file, request.position),
         {:ok, ls_location} <- to_response(request.id, location) do
      {:reply, ls_location}
    else
      {:error, reason} ->
        Logger.error("GoToDefinition failed: #{inspect(reason)}")
        {:error, Responses.GoToDefinition.error(request.id, :request_failed, inspect(reason))}
    end
  end

  defp to_response(request_id, nil) do
    {:ok, Responses.GoToDefinition.new(request_id, nil)}
  end

  defp to_response(request_id, {source_file, range}) do
    with {:ok, ls_range} <- Ranged.Lsp.from_native(range, source_file) do
      ls_location = Location.new(uri: source_file.uri, range: ls_range)
      {:ok, Responses.GoToDefinition.new(request_id, ls_location)}
    end
  end
end
