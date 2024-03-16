defmodule Lexical.RemoteControl.CodeMod.Rename do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeMod.Rename.Prepare

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, term()}
  def prepare(%Analysis{} = analysis, %Position{} = position) do
    Prepare.prepare(analysis, position)
  end

  @renamable_mapping %{call: __MODULE__.Callable, module: __MODULE__.Module}

  @spec rename(Analysis.t(), Position.t(), String.t()) ::
          {:ok, %{Lexical.uri() => [Edit.t()]}} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name) do
    case Prepare.resolve(analysis, position) do
      {:ok, {renamable, entity}, range} ->
        rename_module = @renamable_mapping[renamable]
        {:ok, rename_module.rename(range, new_name, entity)}

      {:error, error} ->
        {:error, error}
    end
  end
end
