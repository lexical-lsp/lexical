defmodule Lexical.RemoteControl.CodeMod.Rename.Module do
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

  @spec rename(Range.t(), String.t(), atom()) :: %{Lexical.uri() => [Edit.t()]}
  def rename(%Range{} = old_range, new_name, entity) do
    {old_suffix, new_suffix} = old_range |> range_text() |> diff(new_name)
    results = exacts(entity, old_suffix) ++ descendants(entity, old_suffix)

    Enum.group_by(
      results,
      &Document.Path.ensure_uri(&1.path),
      &Edit.new(new_suffix, &1.range)
    )
  end

  @spec resolve(Analysis.t() | Lexical.path(), Position.t()) ::
          {:ok, {atom(), atom()}, Range.t()} | {:error, term()}
  def resolve(%Analysis{} = analysis, %Position{} = position) do
    case Entity.resolve(analysis, position) do
      {:ok, {module_or_struct, module}, range} when module_or_struct in [:struct, :module] ->
        {:ok, {:module, module}, range}

      _ ->
        {:error, :not_a_module}
    end
  end

  def resolve(path, %Position{} = position) do
    uri = Document.Path.ensure_uri(path)

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, _document, analysis} <- Document.Store.fetch(uri, :analysis) do
      resolve(analysis, position)
    end
  end

  defp diff(old_range_text, new_name) do
    diff = String.myers_difference(old_range_text, new_name)

    eq =
      if match?([{:eq, _eq} | _], diff) do
        diff |> hd() |> elem(1)
      else
        ""
      end

    old_suffix = String.replace(old_range_text, ~r"^#{eq}", "")
    new_suffix = String.replace(new_name, ~r"^#{eq}", "")
    {old_suffix, new_suffix}
  end

  defp exacts(entity, old_suffix) do
    entity
    |> query_for_exacts()
    |> Enum.filter(&entry_matching?(&1, old_suffix))
    |> adjust_range_for_exacts(old_suffix)
  end

  defp descendants(entity, old_suffix) do
    entity
    |> query_for_descendants()
    |> Enum.filter(&(entry_matching?(&1, old_suffix) and has_dots_in_range?(&1)))
    |> adjust_range_for_descendants(entity, old_suffix)
  end

  defp query_for_exacts(entity) do
    entity_string = inspect(entity)

    case Store.exact(entity_string, type: :module) do
      {:ok, entries} -> entries
      {:error, _} -> []
    end
  end

  defp query_for_descendants(entity) do
    prefix = "#{inspect(entity)}."

    case Store.prefix(prefix, type: :module) do
      {:ok, entries} -> entries
      {:error, _} -> []
    end
  end

  defp maybe_rename_file(document, entries, new_suffix) do
    entries
    |> Enum.map(&Rename.File.maybe_rename(document, &1, new_suffix))
    # every group should have only one `rename_file`
    |> Enum.find(&(not is_nil(&1)))
  end

  defp entry_matching?(entry, old_suffix) do
    entry.range |> range_text() |> String.contains?(old_suffix)
  end

  defp has_dots_in_range?(entry) do
    entry.range |> range_text() |> String.contains?(".")
  end

  defp adjust_range_for_exacts(entries, old_suffix) do
    for entry <- entries do
      start_character = entry.range.end.character - String.length(old_suffix)
      start_position = %{entry.range.start | character: start_character}
      range = %{entry.range | start: start_position}
      %{entry | range: range}
    end
  end

  defp adjust_range_for_descendants(entries, entity, old_suffix) do
    for entry <- entries,
        range_text = range_text(entry.range),
        matches = matches(range_text, old_suffix),
        result = resolve_module_range(entry, entity, matches),
        match?({:ok, _}, result) do
      {_, range} = result
      %{entry | range: range}
    end
  end

  defp range_text(range) do
    line(text: text) = range.end.context_line
    String.slice(text, range.start.character - 1, range.end.character - range.start.character)
  end

  defp resolve_module_range(_entry, _entity, []) do
    {:error, :not_found}
  end

  defp resolve_module_range(entry, entity, [[{start, length}]]) do
    range = adjust_range_characters(entry.range, {start, length})

    with {:ok, {:module, result}, _} <- resolve(entry.path, range.start),
         true <- entity == result do
      {:ok, range}
    end
  end

  defp resolve_module_range(entry, entity, [[{start, length}] | tail] = _matches) do
    # This function is mainly for the duplicated suffixes
    # For example, if we have a module named `Foo.Bar.Foo.Bar` and we want to rename it to `Foo.Bar.Baz`
    # The `Foo.Bar` will be duplicated in the range text, so we need to resolve the correct range
    # and only rename the second occurrence of `Foo.Bar`
    start_character = entry.range.start.character + start
    position = %{entry.range.start | character: start_character}

    with {:ok, {:module, result}, range} <- resolve(entry.path, position) do
      if result == entity do
        range = adjust_range_characters(range, {start, length})
        {:ok, range}
      else
        resolve_module_range(entry, entity, tail)
      end
    end
  end

  defp matches(range_text, "") do
    # When expanding a module, the old_suffix is an empty string,
    # so we need to scan the module before the period
    for [{start, length}] <- Regex.scan(~r/\w+(?=\.)/, range_text, return: :index) do
      [{start + length, 0}]
    end
  end

  defp matches(range_text, old_suffix) do
    Regex.scan(~r/#{old_suffix}/, range_text, return: :index)
  end

  defp adjust_range_characters(%Range{} = range, {start, length} = _matched_old_suffix) do
    start_character = range.start.character + start
    end_character = start_character + length

    range
    |> put_in([:start, :character], start_character)
    |> put_in([:end, :character], end_character)
  end
end
