defmodule Lexical.RemoteControl.CodeIntelligence.Rename do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Line
  alias Lexical.Document.Position
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
    cursor_entity_string = cursor_entity_string(range)

    entities =
      exacts(entity, cursor_entity_string)

    # Users won't always want to rename descendants of a module.
    # For instance, when there are no more submodules after the cursor.
    # like: `defmodule TopLevel.Mo|dule do`
    # in most cases, users only want to rename the module itself.
    #
    # However, there's an exception when the cursor is in the middle,
    # such as `Top.Mo|dule.ChildModule`. If we rename it to `Top.Renamed.Child`,
    # it would be natural to also rename `Module.ChildModule` to `Renamed.Child`.
    if at_the_middle_of_module?(document, position, range) do
      entities ++ descendants(entity, cursor_entity_string)
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

  defp cursor_entity_string(range) do
    # Parent.|Module -> Module
    range
    |> range_text()
    |> String.split(".")
    |> List.last()
  end

  defp descendants(entity, cursor_entity_string) do
    entity_string = inspect(entity)
    prefix = "#{entity_string}."

    prefix
    |> Store.prefix(subject: [:definition, :reference])
    |> Enum.filter(&entry_matching?(&1, cursor_entity_string))
    |> adjust_range(entity)
  end

  defp exacts(entity, cursor_entity_string) do
    entity_string = inspect(entity)

    entity_string
    |> Store.exact(subject: [:definition, :reference])
    |> Enum.filter(&entry_matching?(&1, cursor_entity_string))
  end

  defp entry_matching?(entry, cursor_entity_string) do
    range_text = range_text(entry.range)
    String.contains?(range_text, cursor_entity_string)
  end

  defp adjust_range(entries, entity) do
    for entry <- entries,
        uri = Document.Path.ensure_uri(entry.path),
        {:ok, range} = resolve_entity_range(uri, entry.range.start, entity) do
      %{entry | range: range}
    end
  end

  defp resolve_entity_range(uri, position, entity) do
    with {:ok, document} <- Document.Store.open_temporary(uri),
         analysis = Ast.analyze(document),
         {:ok, result, range} <- resolve_module(analysis, position) do
      if result == entity do
        {:ok, range}
      else
        last_part_length = result |> last_part() |> String.length()
        # Move the cursor to the next part:
        # `|Parent.Next.Target.Child` -> 'Parent.|Next.Target.Child' -> 'Parent.Next.|Target.Child'
        character = position.character + last_part_length + 1
        position = Position.new(document, position.line, character)
        resolve_entity_range(uri, position, entity)
      end
    else
      _ ->
        Logger.error("Failed to find entity range for #{inspect(uri)} at #{inspect(position)}")
        :error
    end
  end

  defp last_part(entity) when is_atom(entity) do
    entity
    |> inspect()
    |> String.split(".")
    |> List.last()
  end

  defp to_edits_by_uri(results, new_name) do
    Enum.group_by(
      results,
      fn result -> Document.Path.ensure_uri(result.path) end,
      fn result ->
        cursor_entity_length = result.range |> cursor_entity_string() |> String.length()
        # e.g: `Parent.|ToBeRenameModule`, we need the start position of `ToBeRenameModule`
        start_character = result.range.end.character - cursor_entity_length
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
end
