defmodule Lexical.RemoteControl.CodeIntelligence.Rename do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Line
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Store
  require Logger

  import Line

  @spec rename(Analysis.t(), Position.t(), String.t()) ::
          {:ok, %{Lexical.uri() => [Edit.t()]}} | {:error, term()}
  def rename(%Analysis{} = analysis, %Position{} = position, new_name) do
    with {:ok, entity, range} <- resolve_module(analysis, position) do
      edits =
        analysis.document
        |> search_related_candidates(position, entity, range)
        |> to_edits_by_uri(new_name)

      {:ok, edits}
    end
  end

  @spec prepare(Analysis.t(), Position.t()) :: {:ok, String.t(), Range.t()} | {:error, term()}
  def prepare(%Analysis{} = analysis, %Position{} = position) do
    case resolve_module(analysis, position) do
      {:ok, _, range} ->
        {:ok, local_module_name(range), range}

      {:error, _} ->
        {:error, :unsupported_entity}
    end
  end

  defp resolve_module(analysis, position) do
    case Entity.resolve(analysis, position) do
      {:ok, {module_or_struct, module}, range} when module_or_struct in [:struct, :module] ->
        {:ok, module, range}

      {:ok, other, _} ->
        {:error, {:unsupported_entity, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_related_candidates(document, position, entity, range) do
    local_module_name = local_module_name(range)
    entities = exacts(entity, local_module_name)

    # Users won't always want to rename descendants of a module.
    # For instance, when there are no more submodules after the cursor.
    # like: `defmodule TopLevel.Mo|dule do`
    # in most cases, users only want to rename the module itself.
    #
    # However, there's an exception when the cursor is in the middle,
    # such as `Top.Mo|dule.ChildModule`. If we rename it to `Top.Renamed.Child`,
    # it would be natural to also rename `Module.ChildModule` to `Renamed.Child`.
    if at_the_middle_of_module?(document, position, range) do
      entities ++ descendants(entity, local_module_name)
    else
      entities
    end
  end

  defp at_the_middle_of_module?(document, position, range) do
    range_text = range_text(range)

    case Ast.surround_context(document, position) do
      {:ok, %{context: {:alias, alias}}} ->
        String.length(range_text) < length(alias)

      _ ->
        false
    end
  end

  defp descendants(entity, local_module_name) do
    entity_string = inspect(entity)
    prefix = "#{entity_string}."

    prefix
    |> Store.prefix([])
    |> Enum.filter(&(entry_matching?(&1, local_module_name) and has_dots_in_range?(&1)))
    |> adjust_range(entity)
  end

  defp exacts(entity, local_module_name) do
    entity_string = inspect(entity)

    entity_string
    |> Store.exact([])
    |> Enum.filter(&entry_matching?(&1, local_module_name))
  end

  defp entry_matching?(entry, local_module_name) do
    entry.range |> range_text() |> String.contains?(local_module_name)
  end

  defp has_dots_in_range?(entry) do
    entry.range |> range_text() |> String.contains?(".")
  end

  defp adjust_range(entries, entity) do
    for entry <- entries,
        uri = Document.Path.ensure_uri(entry.path),
        range_result = resolve_local_module_range(uri, entry.range.start, entity),
        match?({:ok, _}, range_result) do
      {_, range} = range_result
      %{entry | range: range}
    end
  end

  defp resolve_local_module_range(uri, position, entity) do
    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, document, analysis} <- Document.Store.fetch(uri, :analysis),
         {:ok, result, range} <- resolve_module(analysis, position) do
      if result == entity do
        {:ok, range}
      else
        last_part_length = result |> Ast.Module.local_module_name() |> String.length()
        # Move the cursor to the next part:
        # `|Parent.Next.Target.Child` -> 'Parent.|Next.Target.Child' -> 'Parent.Next.|Target.Child'
        character = position.character + last_part_length + 1
        position = Position.new(document, position.line, character)
        resolve_local_module_range(uri, position, entity)
      end
    else
      _ ->
        Logger.error("Failed to find entity range for #{inspect(uri)} at #{inspect(position)}")
        :error
    end
  end

  defp to_edits_by_uri(results, new_name) do
    Enum.group_by(
      results,
      &Document.Path.ensure_uri(&1.path),
      fn result ->
        local_module_name_length = result.range |> local_module_name() |> String.length()
        # e.g: `Parent.|ToBeRenameModule`, we need the start position of `ToBeRenameModule`
        start_character = result.range.end.character - local_module_name_length
        start_position = %{result.range.start | character: start_character}

        new_range = %{result.range | start: start_position}
        Edit.new(new_name, new_range)
      end
    )
  end

  defp range_text(range) do
    line(text: text) = range.end.context_line
    String.slice(text, range.start.character - 1, range.end.character - range.start.character)
  end

  defp local_module_name(%Range{} = range) do
    range |> range_text() |> Ast.Module.local_module_name()
  end
end
