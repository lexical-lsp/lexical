defmodule Lexical.Server.Provider.Handlers.FindReferences do
  alias Lexical.Protocol.Requests.FindReferences
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%FindReferences{} = request, %Env{} = env) do
    include_declaration? = !!request.context.include_declaration

    locations =
      case Api.references(env.project, request.document, request.position, include_declaration?) do
        {:ok, locations} ->
          locations

        _ ->
          nil
      end

    response = Responses.FindReferences.new(request.id, locations)
    {:reply, response}
  end
end
