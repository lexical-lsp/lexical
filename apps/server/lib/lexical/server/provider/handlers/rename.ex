defmodule Lexical.Server.Provider.Handlers.Rename do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Protocol.Requests.Rename
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.RenameFile
  alias Lexical.Protocol.Types.TextDocument
  alias Lexical.Protocol.Types.Workspace
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.Provider.Env
  require Logger

  def handle(%Rename{} = request, %Env{} = env) do
    case Document.Store.fetch(request.document.uri, :analysis) do
      {:ok, _document, %Ast.Analysis{valid?: true} = analysis} ->
        rename(request, env, analysis)

      _ ->
        {:reply,
         Responses.Rename.error(request.id, :request_failed, "document can not be analyzed")}
    end
  end

  defp rename(%Rename{} = request, %Env{} = env, analysis) do
    %Rename{id: id, position: position, new_name: new_name} = request
    %Env{project: project, client_name: client_name} = env

    case Api.rename(project, analysis, position, new_name, client_name) do
      {:ok, []} ->
        {:reply, nil}

      {:ok, results} ->
        document_changes =
          Enum.flat_map(results, fn
            %Changes{rename_file: %Changes.RenameFile{}} = changes ->
              [new_text_document_edit(changes), new_rename_file(changes.rename_file)]

            %Changes{} = changes ->
              [new_text_document_edit(changes)]
          end)

        workspace_edit = Workspace.Edit.new(document_changes: document_changes)
        {:reply, Responses.Rename.new(id, workspace_edit)}

      {:error, {:unsupported_entity, entity}} ->
        Logger.info("Cannot rename entity: #{inspect(entity)}")
        {:reply, nil}

      {:error, reason} ->
        {:reply, Responses.Rename.error(id, :request_failed, inspect(reason))}
    end
  end

  defp new_text_document_edit(%Changes{} = changes) do
    %Changes{document: document, edits: edits} = changes

    text_document =
      TextDocument.OptionalVersioned.Identifier.new(uri: document.uri, version: document.version)

    TextDocument.Edit.new(edits: edits, text_document: text_document)
  end

  defp new_rename_file(%Document.Changes.RenameFile{} = rename_file) do
    options = RenameFile.Options.new(overwrite: true)

    RenameFile.new(
      kind: "rename",
      new_uri: rename_file.new_uri,
      old_uri: rename_file.old_uri,
      options: options
    )
  end
end
