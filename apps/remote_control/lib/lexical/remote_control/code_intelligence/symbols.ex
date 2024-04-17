defmodule Lexical.RemoteControl.CodeIntelligence.Symbols do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeIntelligence.Symbols
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Extractors

  @block_types [
    :ex_unit_describe,
    :ex_unit_setup,
    :ex_unit_setup_all,
    :ex_unit_test,
    :module,
    :private_function,
    :public_function
  ]

  @symbol_extractors [
    Extractors.FunctionDefinition,
    Extractors.Module,
    Extractors.ModuleAttribute,
    Extractors.StructDefinition,
    Extractors.ExUnit
  ]

  def for_document(%Document{} = document) do
    {:ok, entries} = Indexer.Source.index_document(document, @symbol_extractors)

    definitions = Enum.filter(entries, &(&1.subtype == :definition))
    to_symbols(document, definitions)
  end

  def for_workspace(query) do
    query
    |> Search.Store.fuzzy([])
    |> Enum.map(&Symbols.Workspace.from_entry/1)
  end

  defp to_symbols(%Document{} = document, entries) do
    entries_by_block_id = Enum.group_by(entries, & &1.block_id)
    rebuild_structure(entries_by_block_id, document, :root)
  end

  defp rebuild_structure(entries_by_block_id, %Document{} = document, block_id) do
    block_entries = Map.get(entries_by_block_id, block_id, [])

    Enum.flat_map(block_entries, fn
      %Entry{type: type, subtype: :definition} = entry when type in @block_types ->
        result =
          if Map.has_key?(entries_by_block_id, entry.id) do
            children =
              entries_by_block_id
              |> rebuild_structure(document, entry.id)
              |> Enum.sort_by(fn %Symbols.Document{} = symbol ->
                start = symbol.range.start
                {start.line, start.character}
              end)

            Symbols.Document.from(document, entry, children)
          else
            Symbols.Document.from(document, entry)
          end

        case result do
          {:ok, symbol} -> [symbol]
          _ -> []
        end

      %Entry{} = entry ->
        case Symbols.Document.from(document, entry) do
          {:ok, symbol} -> [symbol]
          _ -> []
        end
    end)
  end
end
