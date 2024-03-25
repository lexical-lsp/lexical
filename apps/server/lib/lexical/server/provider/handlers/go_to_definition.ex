defmodule Lexical.Server.Provider.Handlers.GoToDefinition do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.Protocol.Responses
  alias Lexical.RemoteControl

  require Logger

  def handle(%GoToDefinition{} = request, env) do
    with {:ok, _document, %Ast.Analysis{valid?: true} = analysis} <-
           Document.Store.fetch(request.document.uri, :analysis),
         {:ok, location} <- RemoteControl.Api.definition(env.project, analysis, request.position) do
      {:reply, Responses.GoToDefinition.new(request.id, location)}
    else
      {:error, reason} ->
        Logger.error("GoToDefinition failed: #{inspect(reason)}")
        {:reply, Responses.GoToDefinition.error(request.id, :request_failed, inspect(reason))}
    end
  end
end
