defmodule Lexical.RemoteControl.Search.Store.Backend do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  @type version :: pos_integer()

  @type load_state :: :empty | :stale
  @type field_name :: atom()
  @type name :: term
  @type metadata :: %{
          schema_version: version(),
          types: [Entry.entry_type()],
          subtypes: [Entry.entry_subtype()]
        }

  @callback new(Path.t()) :: {:ok, load_state(), name()} | {:error, :any}
  @callback new(Path.t(), version()) :: {:ok, load_state(), name()} | {:error, any()}
  @callback insert([Entry.t()]) :: :ok
  @callback drop() :: boolean()
  @callback select_all :: [Entry.t()]
  @callback select_unique_fields([field_name()]) :: [Entry.t()]
  @callback replace_all([Entry.t()]) :: :ok
  @callback find_metadata() :: metadata
  @callback find_by_subject(Entry.subject(), Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]
  @callback find_by_references([reference()], Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]
end
