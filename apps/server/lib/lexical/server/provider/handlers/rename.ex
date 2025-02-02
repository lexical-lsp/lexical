defmodule Lexical.Server.Provider.Handlers.Rename do
  alias Lexical.Ast
  alias Lexical.Document
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
        rename(
          env.project,
          analysis,
          request.position,
          request.new_name,
          request.id,
          env.client_name
        )

      _ ->
        {:reply,
         Responses.Rename.error(request.id, :request_failed, "document can not be analyzed")}
    end
  end

  defp rename(project, analysis, position, new_name, id, client_name) do
    case Api.rename(project, analysis, position, new_name, client_name) do
      {:ok, []} ->
        {:reply, nil}

      {:ok, results} ->
        text_document_edits =
          Enum.map(results, fn %Document.Changes{edits: edits, document: document} ->
            new_text_document_edit(document.uri, edits)
          end)

        rename_files =
          results
          |> Stream.map(& &1.rename_file)
          |> Stream.reject(&(&1 == nil))
          |> Enum.map(&new_rename_file/1)

        workspace_edit = Workspace.Edit.new(document_changes: text_document_edits ++ rename_files)

        {:reply, Responses.Rename.new(id, workspace_edit)}

      {:error, {:unsupported_entity, entity}} ->
        Logger.info("Unrenameable entity: #{inspect(entity)}")
        {:reply, nil}

      {:error, reason} ->
        {:reply, Responses.Rename.error(id, :request_failed, inspect(reason))}
    end
  end

  defp new_text_document_edit(uri, edits) do
    # NOTE: the `0` here is for use in VSCode.
    # Before May 4, 2024, if this `0` number is not set,
    # the rename function in VSCode will not work,
    # while other editors seem not to care about this field.
    text_document = TextDocument.OptionalVersioned.Identifier.new(uri: uri, version: 0)
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
