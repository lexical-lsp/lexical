defmodule Lexical.Server.Provider.Handlers.PrepareRename do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Protocol.Requests.PrepareRename
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Provider.Env

  def handle(%PrepareRename{} = request, %Env{} = env) do
    case Document.Store.fetch(request.document.uri, :analysis) do
      {:ok, _document, %Ast.Analysis{valid?: true} = analysis} ->
        prepare_rename(env.project, analysis, request.position, request.id)

      _ ->
        {:reply,
         Responses.PrepareRename.error(
           request.id,
           :request_failed,
           "document can not be analyzed"
         )}
    end
  end

  defp prepare_rename(project, analysis, position, id) do
    case Api.prepare_rename(project, analysis, position) do
      {:ok, cursor_entity, range} ->
        result =
          Types.PrepareRenameResult.PrepareRenameResult.new(
            placeholder: cursor_entity,
            range: range
          )

        {:reply, Responses.PrepareRename.new(id, result)}

      _ ->
        {:reply, Responses.PrepareRename.new(id, nil)}
    end
  end
end
