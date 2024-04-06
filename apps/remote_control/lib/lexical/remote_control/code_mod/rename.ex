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

  @spec rename(Analysis.t(), Position.t(), String.t()) ::
          {:ok, [Document.Changes.t()]} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name) do
    with {:ok, {renamable, entity}, range} <- Rename.Prepare.resolve(analysis, position) do
      rename_module = @rename_mapping[renamable]
      results = rename_module.rename(range, new_name, entity)
      set_rename_progress(results)
      {:ok, results}
    end
  end

  defp set_rename_progress(document_changes_list) do
    uri_with_operation_counts =
      document_changes_list
      |> Enum.flat_map(fn %Document.Changes{document: document, rename_file: rename_file} ->
        if rename_file do
          [{rename_file.old_uri, 2}, {rename_file.new_uri, 1}]
        else
          [{document.uri, 3}]
        end
      end)
      |> Map.new()

    Commands.Rename.set_rename_progress(uri_with_operation_counts)
  end
end
