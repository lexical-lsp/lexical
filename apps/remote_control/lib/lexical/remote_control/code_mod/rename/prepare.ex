defmodule Lexical.RemoteControl.CodeMod.Rename.Prepare do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.CodeMod.Rename
  alias Lexical.RemoteControl.Search.Store

  require Logger

  @spec prepare(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, term()}
  def prepare(%Analysis{} = analysis, %Position{} = position) do
    case resolve(analysis, position) do
      {:ok, {:module, module}, range} ->
        {:ok, Formats.module(module), range}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec resolve(Analysis.t(), Position.t()) ::
          {:ok, {atom(), atom()} | {atom(), tuple()}, Range.t()} | {:error, term()}
  def resolve(%Analysis{} = analysis, %Position{} = position) do
    case do_resolve(analysis, position) do
      {:ok, {:module, _module}, _range} ->
        {module, range} = surround_the_whole_module(analysis, position)

        if cursor_at_declaration?(module, range) do
          {:ok, {:module, module}, range}
        else
          {:error, {:unsupported_location, :module}}
        end

      other ->
        other
    end
  end

  defp surround_the_whole_module(analysis, position) do
    # When renaming occurs, we want users to be able to choose any place in the defining module,
    # not just the last local module, like: `defmodule |Foo.Bar do` also works.
    {:ok, %{end: {_end_line, end_character}}} = Ast.surround_context(analysis, position)
    end_position = %{position | character: end_character - 1}
    {:ok, {:module, module}, range} = do_resolve(analysis, end_position)
    {module, range}
  end

  defp cursor_at_declaration?(module, rename_range) do
    case Store.exact(module, type: :module, subtype: :definition) do
      {:ok, [definition]} ->
        rename_range == definition.range

      _ ->
        false
    end
  end

  @renamable_modules [Rename.Module]

  defp do_resolve(%Analysis{} = analysis, %Position{} = position) do
    result =
      Enum.find_value(@renamable_modules, fn module ->
        result = module.resolve(analysis, position)

        if match?({:ok, _, _}, result) do
          result
        end
      end)

    if is_nil(result) do
      case Entity.resolve(analysis, position) do
        {:ok, other, _} ->
          Logger.info("Unsupported entity for renaming: #{inspect(other)}")
          {:error, :unsupported_entity}

        {:error, reason} ->
          {:error, reason}
      end
    else
      result
    end
  end
end
