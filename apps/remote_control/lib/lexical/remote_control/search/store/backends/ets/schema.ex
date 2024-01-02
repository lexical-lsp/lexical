defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schema do
  @moduledoc """
  A use-able module that allows ETS schemas to be created and migrated.

  This module allows users to define ETS key-based schemas for our search backends. These modules
  are versioned, and are all stored in their own ETS tables. This is so that a single ETS table can
  never have more than one schema.

  Schemas also support migrations. An optional `migrate` function receives old entries and is expected
  transform them into the newer version. The results of this function will be loaded into the schema's
  ETS table. If an empty list is returned, a full reindex will take place.
  """
  defmacro __using__(opts) do
    version = Keyword.fetch!(opts, :version)

    quote do
      @version unquote(version)
      alias Lexical.Project
      import unquote(__MODULE__), only: [defkey: 2]

      def version do
        @version
      end

      def index_file_name do
        "source.index.v#{@version}.ets"
      end

      def table_name do
        :"lexical_search_v#{@version}"
      end

      def table_options do
        [:named_table, :set]
      end

      def migrate(entries) do
        {:ok, entries}
      end

      defoverridable migrate: 1, index_file_name: 0, table_options: 0
    end
  end

  defmacro defkey(name, fields) do
    query_keys = Enum.map(fields, fn name -> {name, :_} end)
    query_record_name = :"query_#{name}"

    quote location: :keep do
      require Record

      Record.defrecord(unquote(name), unquote(fields))
      Record.defrecord(unquote(query_record_name), unquote(name), unquote(query_keys))
    end
  end

  alias Lexical.Project
  alias Lexical.VM.Versions

  def load(%Project{} = project, schema_order) do
    ensure_unique_versions(schema_order)
    ensure_index_directory_exists(project)

    case upgrade_chain(project, schema_order) do
      {:ok, [[schema_module]]} ->
        # this case is that there are no migrations to perform
        # we get a single entry, which is the schema module
        {table_name, entries} = load_initial(project, schema_module)
        {:ok, table_name, load_status(entries)}

      {:ok, [[initial, _] | _] = chain} ->
        {table_name, entries} = load_initial(project, initial)

        case apply_migrations(project, chain, entries) do
          {:ok, schema_module, entries} ->
            dest_table_name = populate_schema_table(schema_module, entries)
            :ets.delete(table_name)
            {:ok, dest_table_name, load_status(entries)}

          error ->
            error
        end

      :error ->
        schema_module = List.last(schema_order)
        table_name = schema_module.table_name()
        ensure_schema_table_exists(table_name, schema_module.table_options())
        {:ok, table_name, :empty}
    end
  end

  def index_root(%Project{} = project) do
    versions = Versions.current()
    index_path = ["indexes", versions.erlang, versions.elixir]
    Project.workspace_path(project, index_path)
  end

  def index_file_path(%Project{} = project, schema) do
    project
    |> index_root()
    |> Path.join(schema.index_file_name())
  end

  defp load_status([]), do: :empty
  defp load_status(_entries), do: :stale

  defp apply_migrations(%Project{} = project, chain, entries) do
    Enum.reduce_while(chain, {:ok, nil, entries}, fn
      [current], {:ok, _, entries} ->
        {:halt, {:ok, current, entries}}

      [from, to], {:ok, _, entries} ->
        with {:ok, new_entries} <- to.migrate(entries),
             :ok <- remove_old_schema_file(project, from) do
          {:cont, {:ok, to, new_entries}}
        else
          error ->
            {:halt, error}
        end
    end)
  end

  defp populate_schema_table(schema_module, entries) do
    dest_table_name = schema_module.table_name()
    ensure_schema_table_exists(dest_table_name, schema_module.table_options())
    :ets.delete_all_objects(dest_table_name)
    :ets.insert(dest_table_name, entries)
    dest_table_name
  end

  defp ensure_schema_table_exists(table_name, table_options) do
    case :ets.whereis(table_name) do
      :undefined -> :ets.new(table_name, table_options)
      _ -> table_name
    end
  end

  defp load_initial(%Project{} = project, schema_module) do
    filename =
      project
      |> index_file_path(schema_module)
      |> String.to_charlist()

    table_name = schema_module.table_name()

    entries =
      case :ets.file2tab(filename) do
        {:ok, ^table_name} ->
          :ets.tab2list(table_name)

        {:ok, other_name} ->
          # the data file loaded was saved from some other module
          # likely due to namespacing. We delete the table and create
          # another one with the correct name.
          entries = :ets.tab2list(other_name)
          :ets.delete(other_name)
          ensure_schema_table_exists(table_name, schema_module.table_options())
          :ets.insert(table_name, entries)
          entries
      end

    {table_name, entries}
  end

  defp upgrade_chain(%Project{} = project, schema_order) do
    filtered =
      schema_order
      |> Enum.chunk_every(2, 1)
      |> Enum.filter(fn
        [schema_module | _] ->
          File.exists?(index_file_path(project, schema_module))
      end)

    case filtered do
      [] ->
        :error

      other ->
        {:ok, other}
    end
  end

  defp remove_old_schema_file(%Project{} = project, schema_module) do
    File.rm(index_file_path(project, schema_module))
  end

  defp ensure_index_directory_exists(%Project{} = project) do
    project
    |> index_root()
    |> File.mkdir_p!()
  end

  defp ensure_unique_versions(schemas) do
    Enum.reduce(schemas, %{}, fn schema, seen_versions ->
      schema_version = schema.version()

      case seen_versions do
        %{^schema_version => previous_schema} ->
          message =
            "Version Conflict. #{inspect(schema)} had a version that matches #{inspect(previous_schema)}"

          raise ArgumentError.exception(message)

        _ ->
          Map.put(seen_versions, schema_version, schema)
      end
    end)
  end
end
