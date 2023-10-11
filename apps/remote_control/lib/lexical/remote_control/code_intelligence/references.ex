defmodule Lexical.RemoteControl.CodeIntelligence.References do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store

  require Logger

  def references({:module, module}) do
    module_references(module)
  end

  def references({:struct, struct_module}) do
    module_references(struct_module)
  end

  def references(resolved) do
    Logger.info("Not attempting to find references for unhandled type: #{inspect(resolved)}")
    []
  end

  defp module_references(module) do
    with {:ok, entities} <- Store.exact(module, type: :module, subtype: :reference) do
      locations = Enum.map(entities, &to_location/1)
      {:ok, locations}
    end
  end

  defp to_location(%Entry{} = entry) do
    uri = Document.Path.ensure_uri(entry.path)
    Location.new(entry.range, uri)
  end
end
