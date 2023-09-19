defmodule Lexical.RemoteControl.Search.Store.Ets do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backend
  alias Lexical.VM.Versions
  import Record

  @behaviour Backend
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

  @field_names [:reference, :path, :type, :subtype, :subject, :elixir_version, :erlang_version]

  @doc """
  A header for the records stored in the ETS table / disk.
  The default values are initialized to nil, which represents an unset field.
  """
  defrecord :header, :record_v1, Keyword.new(@field_names, &{&1, nil})

  # A header for the records stored in the ETS table / disk.
  # The default values are initialized to :_ to allow this to be used for querying,
  # as :_ means wildcard to ETS.
  defrecordp :query, :record_v1, Keyword.new(@field_names, &{&1, :_})

  @table __MODULE__

  @impl Backend
  def new(%Project{} = project) do
    new(project, @version)
  end

  def new(%Project{} = project, version \\ @version) do
    file_name = index_file_path(project)
    ensure_index_directory_exists(file_name)

    path_charlist = String.to_charlist(file_name)

    with {:error, _} <- new_from_file(path_charlist) do
      new_table(path_charlist, version)
    end
  end

  @impl Backend
  def drop do
    :ets.delete_all_objects(@table)
  end

  @impl Backend
  def destroy(%Project{} = project) do
    case :ets.info(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(@table)
    end

    project
    |> index_file_path()
    |> File.rm()
  end

  def load_from(filename) when is_binary(filename) do
    filename
    |> String.to_charlist()
    |> load_from()
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

  @impl Backend
  def sync(%Project{} = project) do
    project
    |> index_file_path()
    |> sync_to()
  end

  def sync_to(filename) when is_binary(filename) do
    sync_to(String.to_charlist(filename))
  end

  def sync_to(filename) do
    :ets.tab2file(@table, filename)
  end

  @impl Backend
  def insert(entries) do
    true = :ets.insert(@table, Enum.map(entries, &to_ets/1))
    :ok
  end

  @impl Backend
  def select_all do
    entry_wildcard = match_spec(:_, :_, :_)
    :ets.select(@table, entry_wildcard)
  end

  @impl Backend
  def replace_all([]) do
    true = :ets.match_delete(@table, {query(), :_})
    :ok
  end

  def replace_all(entries) do
    entry_wildcard = {query(), :_}
    rows = Enum.map(entries, &to_ets/1)

    with true <- :ets.match_delete(@table, entry_wildcard),
         true <- :ets.insert(@table, rows) do
      :ok
    end
  end

  @impl Backend
  def find_by_subject(subject, type, subtype) do
    match_spec = match_spec(subject, type, subtype)
    :ets.select(@table, match_spec)
  end

  @impl Backend
  def find_by_refs(references, type, subtype) when is_list(references) do
    for reference <- references,
        match_spec = reference_match_spec(reference, type, subtype),
        result = select_one(match_spec),
        result != nil do
      result
    end
  end

  @impl Backend
  def delete_by_path(path) do
    versions = Versions.current()

    by_path =
      query(
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

  def find_metadata do
    [[result]] = :ets.match(@table, {:metadata, :"$1"})
    metadata(schema_version: version, types: types, subtypes: subtypes) = result
    %{schema_version: version, types: types, subtypes: subtypes}
  end

  defp match_spec(subject, type, subtype) do
    versions = Versions.current()

    header =
      query(
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
      query(
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

  defp to_ets(%Entry{} = entry) do
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

  defp new_from_file(path_charlist) do
    with {:ok, _} <- File.stat(path_charlist),
         {:ok, _table} <- :ets.file2tab(path_charlist) do
      {:ok, :stale}
    end
  end

  defp new_table(path_charlist, version) do
    table_name = :ets.new(@table, [:named_table, :set, read_concurrency: true])
    :ets.insert(table_name, {:metadata, metadata(schema_version: version)})

    case :ets.tab2file(table_name, path_charlist) do
      :ok -> {:ok, :empty}
      error -> error
    end
  end

  defp index_file_path(%Project{} = project) do
    Project.workspace_path(project, Path.join("indexes", "source.index.ets"))
  end

  defp ensure_index_directory_exists(index_path) do
    dir_name = Path.dirname(index_path)
    File.mkdir_p!(dir_name)
  end
end
