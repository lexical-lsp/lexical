defmodule Lexical.RemoteControl.Search.Store.Backend do
  @moduledoc """
  A behaviour for search store backends
  """
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  @type version :: pos_integer()

  @type new_return :: term()
  @type load_state :: :empty | :stale
  @type field_name :: atom()
  @type name :: term
  @type metadata :: %{
          schema_version: version(),
          types: [Entry.entry_type()],
          subtypes: [Entry.entry_subtype()]
        }

  @doc """
  Create a new backend.
  This function must return quickly, as it's called from the store process
  """
  @callback new(Project.t()) :: {:ok, new_return()} | {:error, any()}

  @doc """
  Prepares the backend for use.
  This receives the result of `new/1`, and sets up the store for use. When this function
  returns, the backend is considered ready for use.
  """
  @callback prepare(new_return()) :: {:ok, load_state()}

  @doc """
  Syncs the backend to the file system (optional)
  """
  @callback sync(Project.t()) :: :ok | {:error, any()}

  @doc """
  Inserts all entries into the backend
  """
  @callback insert([Entry.t()]) :: :ok

  @doc """
  Drops all data from the backend, but keeps the underlying structure
  """
  @callback drop() :: boolean()

  @doc """
  Drops all data from the backend, and disposes of any underlying structure
  """
  @callback destroy(Project.t()) :: :ok

  @doc """
  Returns all entries current residing in the backend
  """
  @callback select_all :: [Entry.t()]

  @doc """
  Replaces _all_ the entries in the store with those passed in
  """
  @callback replace_all([Entry.t()]) :: :ok

  @doc """
  Deletes all entries whose path is equal to the one passed in.
  """
  @callback delete_by_path(Path.t()) :: {:ok, [Entry.t()]} | {:error, any()}

  @doc """
  Finds all entries
  """
  @callback find_by_subject(Entry.subject(), Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]

  @doc """
  Finds entries whose ref attribute is in the given list
  """
  @callback find_by_refs([reference()], Entry.entry_type(), Entry.entry_subtype()) :: [
              Entry.t()
            ]

  @optional_callbacks sync: 1
end
