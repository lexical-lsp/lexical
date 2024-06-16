defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Project
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl

  require Logger

  def handle(%GoToDefinition{} = request, %Project{} = project) do
    case RemoteControl.Api.definition(project, request.document, request.position) do
      {:ok, native_location} ->
        {:reply, Responses.GoToDefinition.new(request.id, native_location)}

      {:error, reason} ->
        Logger.error("GoToDefinition failed: #{inspect(reason)}")
        {:reply, Responses.GoToDefinition.new(request.id, nil)}
    end
  end
end
