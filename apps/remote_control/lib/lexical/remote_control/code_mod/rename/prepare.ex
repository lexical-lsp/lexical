defmodule Lexical.RemoteControl.CodeMod.Rename.Prepare do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Line
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeIntelligence.Entity

  import Line

  @spec prepare(Analysis.t(), Position.t()) :: {:ok, String.t(), Range.t()} | {:error, term()}
  def prepare(%Analysis{} = analysis, %Position{} = position) do
    case resolve_module(analysis, position) do
      {:ok, _, range} ->
        {:ok, local_module_name(range), range}

      {:error, _} ->
        {:error, :unsupported_entity}
    end
  end

  def resolve_module(analysis, position) do
    case Entity.resolve(analysis, position) do
      {:ok, {module_or_struct, module}, range} when module_or_struct in [:struct, :module] ->
        {:ok, module, range}

      {:ok, other, _} ->
        {:error, {:unsupported_entity, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def range_text(range) do
    line(text: text) = range.end.context_line
    String.slice(text, range.start.character - 1, range.end.character - range.start.character)
  end

  def local_module_name(%Range{} = range) do
    range |> range_text() |> Ast.Module.local_name()
  end
end
