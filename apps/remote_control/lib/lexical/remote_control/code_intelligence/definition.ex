defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias ElixirSense.Providers.Location, as: ElixirSenseLocation
  alias Future.Code
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.Formats
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.Text

  require Logger

  @spec definition(Document.t(), Position.t()) :: {:ok, [Location.t()]} | {:error, String.t()}
  def definition(%Document{} = document, %Position{} = position) do
    with {:ok, _, analysis} <- Document.Store.fetch(document.uri, :analysis),
         {:ok, entity, _range} <- Entity.resolve(analysis, position) do
      fetch_definition(entity, analysis, position)
    end
  end

  defp fetch_definition({type, _entity} = resolved, %Analysis{} = analysis, %Position{} = pos)
       when type in [:struct, :module] do
    with {:ok, nil} <- exact_module_definition(resolved) do
      elixir_sense_definition(analysis, pos)
    end
  end

  defp fetch_definition({:call, _m, _f, _a} = resolved, %Analysis{} = nlss, %Position{} = pos) do
    with {:ok, nil} <- exact_call_definition(resolved, nlss, pos),
         {:ok, nil} <- elixir_sense_definition(nlss, pos) do
      nearest_arity_call_definition(resolved, nlss, pos)
    end
  end

  defp fetch_definition(_, %Analysis{} = analysis, %Position{} = position) do
    elixir_sense_definition(analysis, position)
  end

  defp exact_module_definition({type, entity} = resolved) do
    module = Formats.module(entity)

    locations =
      module
      |> query_search_index_exact(type: type, subtype: :definition)
      |> entries_to_locations()

    case locations do
      [location] ->
        {:ok, location}

      [_ | _] ->
        {:ok, locations}

      [] ->
        Logger.info("No definition found for #{inspect(resolved)} with Indexer.")
        {:ok, nil}
    end
  end

  defp exact_call_definition({:call, module, function, arity} = resolved, analysis, position) do
    mfa = Formats.mfa(module, function, arity)

    locations =
      mfa
      |> query_search_index_exact(subtype: :definition)
      |> Stream.flat_map(&resolve_defdelegate/1)
      |> Stream.uniq_by(& &1.subject)
      |> maybe_reject_private_defs(module, analysis, position)
      |> entries_to_locations()

    case locations do
      [location] ->
        {:ok, location}

      [_ | _] ->
        {:ok, locations}

      [] ->
        Logger.info("No definition found for #{inspect(resolved)} with Indexer.")
        {:ok, nil}
    end
  end

  defp nearest_arity_call_definition({:call, m, f, _a} = resolved, nlss, pos) do
    mf_prefix = Formats.mf(m, f)

    locations =
      mf_prefix
      |> query_search_index_prefix(subtype: :definition)
      |> Stream.flat_map(&resolve_defdelegate/1)
      |> Stream.uniq_by(& &1.subject)
      |> maybe_reject_private_defs(m, nlss, pos)
      |> Enum.sort(fn %Entry{} = a, %Entry{} = b ->
        String.last(a.subject) < String.last(b.subject)
      end)
      |> Enum.take(1)
      |> entries_to_locations()

    case locations do
      [location] ->
        {:ok, location}

      [_ | _] ->
        {:ok, locations}

      [] ->
        Logger.info("No nearest-arity definition found for #{inspect(resolved)} with Indexer.")
        {:ok, nil}
    end
  end

  def resolve_defdelegate(%Entry{type: {:function, :delegate}} = entry) do
    mfa = get_in(entry, [:metadata, :original_mfa])
    query_search_index_exact(mfa, subtype: :definition) ++ [entry]
  end

  def resolve_defdelegate(entry) do
    [entry]
  end

  defp maybe_reject_private_defs(entries, module, analysis, position) do
    case Analyzer.current_module(analysis, position) do
      {:ok, module_at_position} ->
        if module != module_at_position do
          Stream.reject(entries, &(&1.type == {:function, :private}))
        else
          entries
        end

      :error ->
        entries
    end
  end

  defp entries_to_locations(entries) do
    for entry <- entries,
        result = to_location(entry),
        match?({:ok, _}, result) do
      {:ok, location} = result
      location
    end
  end

  defp elixir_sense_definition(%Analysis{} = analysis, %Position{} = position) do
    analysis.document
    |> Document.to_string()
    |> ElixirSense.definition(position.line, position.character)
    |> parse_location(analysis.document)
  end

  defp parse_location(%ElixirSenseLocation{} = location, document) do
    %{file: file, line: line, column: column, type: type} = location
    file_path = file || document.path
    uri = Document.Path.ensure_uri(file_path)

    with {:ok, document} <- Document.Store.open_temporary(uri),
         {:ok, text} <- Document.fetch_text_at(document, line) do
      {line, column} = maybe_move_cursor_to_next_token(type, document, line, column)
      range = to_precise_range(document, text, line, column)
      {:ok, Location.new(range, document)}
    else
      _ ->
        {:error, "Could not open source file or fetch line text: #{inspect(file_path)}"}
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp maybe_move_cursor_to_next_token(type, document, line, column)
       when type in [:function, :module, :macro] do
    position = Position.new(document, line, column)

    with {:ok, zipper} <- Ast.zipper_at(document, position),
         %{node: {entity_name, meta, _}} <- Sourceror.Zipper.next(zipper) do
      meta =
        if entity_name == :when do
          %{node: {_entity_name, meta, _}} = Sourceror.Zipper.next(zipper)
          meta
        else
          meta
        end

      {meta[:line], meta[:column]}
    else
      _ ->
        {line, column}
    end
  end

  defp maybe_move_cursor_to_next_token(_, _, line, column), do: {line, column}

  defp to_precise_range(%Document{} = document, text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        Entity.to_range(document, start_pos, end_pos)

      _ ->
        # If the column is 1, but the code doesn't start on the first column, which isn't what we want.
        # The cursor will be placed to the left of the actual definition.
        column = if column == 1, do: Text.count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        Entity.to_range(document, pos, pos)
    end
  end

  defp to_location(entry) do
    uri = Document.Path.ensure_uri(entry.path)

    case Document.Store.open_temporary(uri) do
      {:ok, document} ->
        {:ok, Location.new(entry.range, document)}

      _ ->
        :error
    end
  end

  defp query_search_index_exact(subject, constraints) do
    case Store.exact(subject, constraints) do
      {:ok, entries} ->
        entries

      _ ->
        []
    end
  end

  defp query_search_index_prefix(subject, constraints) do
    case Store.prefix(subject, constraints) do
      {:ok, entries} ->
        entries

      _ ->
        []
    end
  end
end
