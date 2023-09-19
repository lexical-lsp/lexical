defmodule Lexical.RemoteControl.Search.Store.Backend do
  @moduledoc """
  A behaviour for search store backends
  """
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  @type version :: pos_integer()

  @type priv_state :: term()
  @type load_state :: :empty | :stale
  @type field_name :: atom()
  @type name :: term
  @type metadata :: %{
          schema_version: version(),
          types: [Entry.entry_type()],
          subtypes: [Entry.entry_subtype()]
        }

  @type wildcard :: :_
  @type subject_query :: Entry.subject() | wildcard()
  @type type_query :: Entry.entry_type() | wildcard()
  @type subtype_query :: Entry.entry_subtype() | wildcard()

  @doc """
  Create a new backend.
  This function must return quickly, as it's called from the store process
  """
  @callback new(Project.t()) :: {:ok, priv_state()} | {:error, any()}

  @doc """
  Prepares the backend for use.
  This receives the result of `new/1`, and sets up the store for use. When this function
  returns, the backend is considered ready for use.
  """
  @callback prepare(priv_state()) :: {:ok, load_state()}

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
  Returns all entries currently residing in the backend
  """
  @callback select_all :: [Entry.t()]

  @doc """
  Replaces all the entries in the store with those passed in
  """
  @callback replace_all([Entry.t()]) :: :ok

  @doc """
  Deletes all entries whose path is equal to the one passed in.
  """
  @callback delete_by_path(Path.t()) :: {:ok, [reference()]} | {:error, any()}

  @doc """
  Finds all entries
  """
  @callback find_by_subject(subject_query(), type_query(), subtype_query()) :: [Entry.t()]

  @doc """
  Finds entries whose ref attribute is in the given list
  """
  @callback find_by_refs([reference()], type_query(), subtype_query()) :: [Entry.t()]

  @optional_callbacks sync: 1
end
