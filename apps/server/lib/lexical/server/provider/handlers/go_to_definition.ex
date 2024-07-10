defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl
  alias Lexical.Server.Configuration

  require Logger

  def handle(%GoToDefinition{} = request, %Configuration{} = config) do
    case RemoteControl.Api.definition(config.project, request.document, request.position) do
      {:ok, native_location} ->
        {:reply, Responses.GoToDefinition.new(request.id, native_location)}

      {:error, reason} ->
        Logger.error("GoToDefinition failed: #{inspect(reason)}")
        {:reply, Responses.GoToDefinition.new(request.id, nil)}
    end
  end
end
