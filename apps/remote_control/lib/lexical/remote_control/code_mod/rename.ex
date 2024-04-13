defmodule Lexical.RemoteControl.CodeMod.Rename do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.Commands
  alias __MODULE__

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, term()}
  defdelegate prepare(analysis, position), to: Rename.Prepare

  @rename_mapping %{module: Rename.Module}

  @spec rename(Analysis.t(), Position.t(), String.t(), String.t() | nil) ::
          {:ok, [Document.Changes.t()]} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name, client_name) do
    with {:ok, {renamable, entity}, range} <- Rename.Prepare.resolve(analysis, position) do
      rename_module = @rename_mapping[renamable]
      results = rename_module.rename(range, new_name, entity)
      set_rename_progress(results, client_name)
      {:ok, results}
    end
  end

  defp set_rename_progress(document_changes_list, client_name) do
    client_name
    |> uri_with_operation_counts(document_changes_list)
    |> Commands.Rename.set_rename_progress()
  end

  defp uri_with_operation_counts("Visual Studio Code", document_changes_list) do
    document_changes_list
    |> Enum.flat_map(fn %Document.Changes{document: document, rename_file: rename_file} ->
      if rename_file do
        # first operation is for `DidChange` in the old file,
        # Note: `DidSave` won't be received for the old file
        # second operation is for `DidSave` in the new file
        [{rename_file.old_uri, 1}, {rename_file.new_uri, 1}]
      else
        [{document.uri, 2}]
      end
    end)
    |> Map.new()
  end

  defp uri_with_operation_counts(_, document_changes_list) do
    document_changes_list
    |> Enum.flat_map(fn %Document.Changes{document: document, rename_file: rename_file} ->
      if rename_file do
        # first operation is for `DidChange`
        # second operation is for `DidSave`
        [{document.uri, 2}]
      else
        # when the file is not renamed, we'll only received `DidChange` for the old file
        [{document.uri, 1}]
      end
    end)
    |> Map.new()
  end
end
