defmodule Lexical.RemoteControl.CodeMod.Rename do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias __MODULE__

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, term()}
  defdelegate prepare(analysis, position), to: Rename.Prepare

  @rename_mapping %{module: Rename.Module}

  @spec rename(Analysis.t(), Position.t(), String.t()) ::
          {:ok, %{Lexical.uri() => [Edit.t()]}} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name) do
    with {:ok, {renamable, entity}, range} <- Rename.Prepare.resolve(analysis, position) do
      rename_module = @rename_mapping[renamable]
      {:ok, rename_module.rename(range, new_name, entity)}
    end
  end
end
