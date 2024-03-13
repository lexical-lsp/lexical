defmodule Lexical.Server.Provider.Handlers.FindReferences do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Protocol.Requests.FindReferences
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%FindReferences{} = request, %Env{} = env) do
    include_declaration? = !!request.context.include_declaration

    locations =
      case Document.Store.fetch(request.document.uri, :analysis) do
        {:ok, _document, %Ast.Analysis{} = analysis} ->
          Api.references(env.project, analysis, request.position, include_declaration?)

        _ ->
          nil
      end

    response = Responses.FindReferences.new(request.id, locations)
    {:reply, response}
  end
end
