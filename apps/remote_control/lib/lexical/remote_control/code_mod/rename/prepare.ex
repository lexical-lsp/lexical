defmodule Lexical.RemoteControl.CodeMod.Rename.Prepare do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.CodeMod.Rename

  require Logger

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()} | nil, Range.t()} | {:error, term()}
  def prepare(%Analysis{} = analysis, %Position{} = position) do
    case resolve(analysis, position) do
      {:ok, {:module, module}, range} ->
        {:ok, Formats.module(module), range}

      {:error, {:unsupported_location, _}} ->
        {:ok, nil}

      {:error, {:unsupported_entity, entity_type}} ->
        {:error, "Renaming #{inspect(entity_type)} is not supported for now"}

      {:error, error} ->
        {:error, error}
    end
  end

  @renaming_modules [Rename.Module]
  @spec resolve(Analysis.t(), Position.t()) ::
          {:ok, {atom(), atom()}, Range.t()} | {:error, tuple() | atom()}
  def resolve(%Analysis{} = analysis, %Position{} = position) do
    prepare_result =
      Enum.find_value(@renaming_modules, fn module ->
        if module.recognizes?(analysis, position) do
          module.prepare(analysis, position)
        end
      end)

    prepare_result || handle_unsupported_entity(analysis, position)
  end

  defp handle_unsupported_entity(analysis, position) do
    with {:ok, other, _range} <- Entity.resolve(analysis, position) do
      Logger.info("Unsupported entity for renaming: #{inspect(other)}")
      {:error, {:unsupported_entity, elem(other, 0)}}
    end
  end
end
