defmodule Lexical.Server.Provider.Handlers.FindReferences do
  alias Lexical.Protocol.Requests.FindReferences
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Responses
  alias Lexical.Server.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%FindReferences{} = request, %Env{} = env) do
    locations =
      case Entity.references(env.project, request.document, request.position) do
        {:ok, locations} ->
          locations

        _ ->
          nil
      end

    response = Responses.FindReferences.new(request.id, locations)
    {:reply, response}
  end
end
