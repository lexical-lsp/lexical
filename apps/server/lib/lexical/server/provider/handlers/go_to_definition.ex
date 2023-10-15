defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl

  require Logger

  def handle(%GoToDefinition{} = request, env) do
    case RemoteControl.Api.definition(env.project, request.document, request.position) do
      {:ok, native_location} ->
        {:reply, Responses.GoToDefinition.new(request.id, native_location)}

      {:error, reason} ->
        Logger.error("GoToDefinition failed: #{inspect(reason)}")
        {:error, Responses.GoToDefinition.error(request.id, :request_failed, inspect(reason))}
    end
  end
end
