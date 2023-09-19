defmodule Lexical.RemoteControl.Search.Store.Backend do
  alias Lexical.Project
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

  @callback new(Project.t()) :: {:ok, load_state()} | {:error, any()}
  @callback sync(Project.t()) :: :ok | {:error, any()}
  @callback insert([Entry.t()]) :: :ok

  @doc """
  Drops all data from the backend, but keeps the underlying structure
  """
  @callback drop() :: boolean()

  @doc """
  Drops all data from the backend, and disposes of any underlying structure
  """
  @callback destroy(Project.t()) :: :ok

  @callback select_all :: [Entry.t()]
  @callback replace_all([Entry.t()]) :: :ok
  @callback delete_by_path(Path.t()) :: {:ok, [Entry.t()]} | {:error, any()}
  @callback find_by_subject(Entry.subject(), Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]
  @callback find_by_refs([reference()], Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]

  @optional_callbacks sync: 1
end
