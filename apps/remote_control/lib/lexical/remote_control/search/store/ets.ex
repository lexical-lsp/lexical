defmodule Lexical.RemoteControl.Search.Store.Ets do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.VM.Versions
  import Record

  @version 1

  @doc """
  Table metadata. This will allow us to detect when and what to redindex if
  we add types or subtypes. It will also allow us to update the header records
  and migrate tables if the need arises.
  """
  defrecord :metadata,
    schema_version: @version,
    types: [:module],
    subtypes: [:definition, :reference]

  @doc """
  A header for the records stored in the ETS table / disk.
  The default values are initialized to :_ to allow this to be used for querying,
  as :_ means wildcard. This _does_ mean you need to

  """
  defrecord :header, :record_v1,
    reference: :_,
    path: :_,
    type: :_,
    subtype: :_,
    subject: :_,
    elixir_version: :_,
    erlang_version: :_

  @table __MODULE__

  def new(version \\ @version) do
    table_name = :ets.new(@table, [:named_table, :set, read_concurrency: true])
    :ets.insert(table_name, {:metadata, metadata(schema_version: version)})
    table_name
  end

  def drop do
    :ets.delete(@table)
  end

  def table_metadata do
    [[result]] = :ets.match(@table, {:metadata, :"$1"})
    metadata(schema_version: version, types: types, subtypes: subtypes) = result
    %{schema_version: version, types: types, subtypes: subtypes}
  end

  def to_ets(%Entry{} = entry) do
    header =
      header(
        reference: entry.ref,
        path: entry.path,
        type: entry.type,
        subtype: entry.subtype,
        elixir_version: entry.elixir_version,
        erlang_version: entry.erlang_version,
        subject: inspect(entry.subject)
      )

    {header, entry}
  end

  def load_from(filename) when is_binary(filename) do
    load_from(String.to_charlist(filename))
  end

  def load_from(filename) do
    with true <- File.exists?(filename),
         {:ok, @table} <- :ets.file2tab(filename) do
      :ok
    else
      _ ->
        :error
    end
  end

  def sync_to(filename) when is_binary(filename) do
    sync_to(String.to_charlist(filename))
  end

  def sync_to(filename) do
    :ets.tab2file(@table, filename)
  end

  def insert(entries) do
    :ets.insert(@table, Enum.map(entries, &to_ets/1))
  end

  def select_all do
    entry_wildcard = match_spec(:_, :_, :_)
    :ets.select(@table, entry_wildcard)
  end

  def select_unique_fields(entry_fields) do
    @table
    |> :ets.select(match_spec(:_, :_, :_))
    |> Stream.map(&Map.take(&1, entry_fields))
    |> Enum.uniq()
  end

  def replace_all([]) do
    :ets.match_delete(@table, {header(), :_})
  end

  def replace_all(entries) do
    entry_wildcard = {header(), :_}
    rows = Enum.map(entries, &to_ets/1)

    with true <- :ets.match_delete(@table, entry_wildcard) do
      :ets.insert(@table, rows)
    end
  end

  def find_exact(subject, type, subtype) do
    match_spec = match_spec(subject, type, subtype)
    :ets.select(@table, match_spec)
  end

  def find_by_ref(type, subtype, references) do
    for reference <- references,
        match_spec = reference_match_spec(reference, type, subtype),
        result = select_one(match_spec),
        result != nil do
      result
    end
  end

  def delete_by_path(path) do
    versions = Versions.current()

    by_path =
      header(
        elixir_version: versions.elixir,
        erlang_version: versions.erlang,
        path: path
      )

    old_entries =
      @table
      |> :ets.match({by_path, :"$1"})
      |> List.flatten()

    with true <- :ets.match_delete(@table, {by_path, :_}) do
      {:ok, old_entries}
    end
  end

  defp match_spec(subject, type, subtype) do
    versions = Versions.current()

    header =
      header(
        elixir_version: versions.elixir,
        erlang_version: versions.erlang,
        subject: subject,
        subtype: subtype,
        type: type
      )

    [{{header, :"$1"}, [], [:"$1"]}]
  end

  defp reference_match_spec(reference, type, subtype) do
    versions = Versions.current()

    header =
      header(
        elixir_version: versions.elixir,
        erlang_version: versions.erlang,
        reference: reference,
        subtype: subtype,
        type: type
      )

    [{{header, :"$1"}, [], [:"$1"]}]
  end

  defp select_one(match_spec) do
    case :ets.select(@table, match_spec) do
      [] -> nil
      [entry] -> entry
    end
  end
end
