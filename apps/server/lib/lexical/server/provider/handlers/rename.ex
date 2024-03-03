defmodule Lexical.Server.Provider.Handlers.Rename do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Protocol.Requests.Rename
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Workspace.Edit
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Provider.Env
  require Logger

  def handle(%Rename{} = request, %Env{} = env) do
    case Document.Store.fetch(request.document.uri, :analysis) do
      {:ok, _document, %Ast.Analysis{valid?: true} = analysis} ->
        rename(env.project, analysis, request.position, request.new_name, request.id)

      _ ->
        {:reply,
         Responses.Rename.error(request.id, :request_failed, "document can not be analyzed")}
    end
  end

  defp rename(project, analysis, position, new_name, id) do
    case Api.rename(project, analysis, position, new_name) do
      {:ok, results} when results == %{} ->
        {:reply, nil}

      {:ok, results} ->
        edit = Edit.new(changes: results)
        {:reply, Responses.Rename.new(id, edit)}

      {:error, {:unsupported_entity, entity}} ->
        Logger.info("Unrenameable entity: #{inspect(entity)}")
        {:reply, nil}

      {:error, reason} ->
        {:reply, Responses.Rename.error(id, :request_failed, inspect(reason))}
    end
  end
end
