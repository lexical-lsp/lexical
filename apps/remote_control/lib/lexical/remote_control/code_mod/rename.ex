defmodule Lexical.RemoteControl.CodeMod.Rename do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeMod.Rename
  alias Lexical.RemoteControl.Commands
  alias Lexical.RemoteControl.Progress

  import Lexical.RemoteControl.Api.Messages

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, term()}
  defdelegate prepare(analysis, position), to: Rename.Prepare

  @rename_mappings %{module: Rename.Module}

  @spec rename(Analysis.t(), Position.t(), String.t(), String.t() | nil) ::
          {:ok, [Document.Changes.t()]} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name, client_name) do
    with {:ok, {renamable, entity}, range} <- Rename.Prepare.resolve(analysis, position) do
      rename_module = Map.fetch!(@rename_mappings, renamable)
      results = rename_module.rename(range, new_name, entity)
      set_rename_progress(results, client_name)
      {:ok, results}
    end
  end

  defp set_rename_progress(document_changes_list, client_name) do
    uri_with_expected_operation =
      uri_with_expected_operation(client_name, document_changes_list)

    {paths_to_delete, paths_to_remind} =
      for %Document.Changes{rename_file: rename_file, document: document} <- document_changes_list do
        if rename_file do
          {rename_file.old_uri, rename_file.new_uri}
        else
          {nil, document.uri}
        end
      end
      |> Enum.unzip()

    paths_to_delete = Enum.reject(paths_to_delete, &is_nil/1)
    renaming_operation_count = Enum.count(uri_with_expected_operation)

    total_operation_count =
      renaming_operation_count + length(paths_to_delete) + length(paths_to_remind)

    {report_progress_func, complete_func} =
      Progress.begin_percent("Renaming", total_operation_count)

    Commands.RenameSupervisor.start_renaming(
      uri_with_expected_operation,
      paths_to_remind,
      paths_to_delete,
      report_progress_func,
      complete_func
    )
  end

  defp uri_with_expected_operation(client_name, document_changes_list)
       when client_name in ["Visual Studio Code"] do
    document_changes_list
    |> Enum.flat_map(fn %Document.Changes{document: document, rename_file: rename_file} ->
      if rename_file do
        # when the file is renamed, we won't receive `DidSave` for the old file
        [
          {rename_file.old_uri, file_changed(uri: rename_file.old_uri)},
          {rename_file.new_uri, file_saved(uri: rename_file.new_uri)}
        ]
      else
        [{document.uri, file_saved(uri: document.uri)}]
      end
    end)
    |> Map.new()
  end

  defp uri_with_expected_operation(_, document_changes_list) do
    document_changes_list
    |> Enum.flat_map(fn %Document.Changes{document: document, rename_file: rename_file} ->
      if rename_file do
        [{rename_file.new_uri, file_saved(uri: rename_file.new_uri)}]
      else
        # Some editors do not directly save the file after renaming, such as *neovim*.
        # when the file is not renamed, we'll only received `DidChange` for the old file
        [{document.uri, file_changed(uri: document.uri)}]
      end
    end)
    |> Map.new()
  end
end
