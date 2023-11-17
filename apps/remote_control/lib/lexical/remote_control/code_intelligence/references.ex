defmodule Lexical.RemoteControl.CodeIntelligence.References do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store

  require Logger

  def references(%Analysis{} = analysis, %Position{} = position, include_definitions?) do
    with {:ok, resolved, _range} <- Entity.resolve(analysis, position) do
      find_references(resolved, include_definitions?)
    end
  end

  defp find_references({:module, module}, include_definitions?) do
    module_references(module, include_definitions?)
  end

  defp find_references({:struct, struct_module}, include_definitions?) do
    module_references(struct_module, include_definitions?)
  end

  defp find_references(resolved, _include_definitions?) do
    Logger.info("Not attempting to find references for unhandled type: #{inspect(resolved)}")
    []
  end

  defp module_references(module, include_definitions?) do
    with {:ok, references} <- Store.exact(module, type: :module, subtype: :reference) do
      entities = maybe_fetch_module_definitions(module, include_definitions?) ++ references
      locations = Enum.map(entities, &to_location/1)
      {:ok, locations}
    end
  end

  defp to_location(%Entry{} = entry) do
    uri = Document.Path.ensure_uri(entry.path)
    Location.new(entry.range, uri)
  end

  defp maybe_fetch_module_definitions(module, true) do
    case Store.exact(module, type: :module, subtype: :definition) do
      {:ok, definitions} -> definitions
      _ -> []
    end
  end

  defp maybe_fetch_module_definitions(_module, false) do
    []
  end
end
