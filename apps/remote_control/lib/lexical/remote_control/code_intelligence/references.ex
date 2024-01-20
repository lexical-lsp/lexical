defmodule Lexical.RemoteControl.CodeIntelligence.References do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.RemoteControl.Search.Subject

  require Logger

  def references(%Analysis{} = analysis, %Position{} = position, include_definitions?) do
    with {:ok, resolved, _range} <- Entity.resolve(analysis, position) do
      find_references(resolved, include_definitions?)
    end
  end

  defp find_references({:module, module}, include_definitions?) do
    subject = Subject.module(module)
    subtype = subtype(include_definitions?)

    query(subject, type: :module, subtype: subtype)
  end

  defp find_references({:struct, struct_module}, include_definitions?) do
    subject = Subject.module(struct_module)
    subtype = subtype(include_definitions?)

    query(subject, type: :struct, subtype: subtype)
  end

  defp find_references({:call, module, function_name, arity}, include_definitions?) do
    subject = Subject.mfa(module, function_name, arity)
    subtype = subtype(include_definitions?)

    query(subject, type: :function, subtype: subtype)
  end

  defp find_references({:module_attribute, module, attribute_name}, include_definitions?) do
    subject = Subject.module_attribute(module, attribute_name)
    subtype = subtype(include_definitions?)

    query(subject, type: :module_attribute, subtype: subtype)
  end

  defp find_references(resolved, _include_definitions?) do
    Logger.info("Not attempting to find references for unhandled type: #{inspect(resolved)}")
    []
  end

  defp to_location(%Entry{} = entry) do
    uri = Document.Path.ensure_uri(entry.path)
    Location.new(entry.range, uri)
  end

  defp query(subject, opts) do
    with {:ok, entities} <- Store.exact(subject, opts) do
      locations = Enum.map(entities, &to_location/1)
      {:ok, locations}
    end
  end

  defp subtype(true = _include_definitions?), do: :_
  defp subtype(false = _include_definitions?), do: :reference
end
