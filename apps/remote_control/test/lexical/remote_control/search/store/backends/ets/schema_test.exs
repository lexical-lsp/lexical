defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.SchemaTest do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema

  import Lexical.Test.Fixtures

  use ExUnit.Case

  setup do
    project = project()

    destroy_index_path(project)

    on_exit(fn ->
      destroy_index_path(project)
    end)

    {:ok, project: project}
  end

  defmodule First do
    use Schema, version: 1
  end

  defmodule IncrementValue do
    use Schema, version: 2

    def migrate(entries) do
      entries = Enum.map(entries, fn {k, v} -> {k, v + 1} end)
      {:ok, entries}
    end
  end

  defmodule IncrementKey do
    use Schema, version: 3

    def migrate(entries) do
      {:ok, Enum.map(entries, fn {k, v} -> {k + 1, v} end)}
    end
  end

  test "it ensures the uniqueness of versions in the schema order", %{project: project} do
    defmodule SameVersion do
      use Schema, version: 1
    end

    assert_raise ArgumentError, fn -> Schema.load(project, [First, SameVersion]) end
  end

  test "it loads an empty index", %{project: project} do
    assert {:ok, _, :empty} = Schema.load(project, [First])
  end

  test "it loads existing entries", %{project: project} do
    entries = [
      {{:ref, 1}, :first},
      {{:ref, 2}, :second}
    ]

    write_entries(project, First, entries)
    assert {:ok, table_name, :stale} = Schema.load(project(), [First])
    assert table_contents(table_name) == entries
  end

  test "allow you to migrate entries", %{project: project} do
    entries = [{1, 1}, {2, 2}, {3, 3}]

    write_entries(project, First, entries)
    assert {:ok, table_name, :stale} = Schema.load(project, [First, IncrementValue])

    assert table_contents(table_name) == [{1, 2}, {2, 3}, {3, 4}]
  end

  test "removes old index files after migration", %{project: project} do
    write_entries(project, First, [])
    assert File.exists?(Schema.index_file_path(project, First))

    assert {:ok, _table_name, :empty} = Schema.load(project, [First, IncrementValue])

    refute File.exists?(Schema.index_file_path(project, First))
  end

  test "migrations that already exist on disk will be reapplied", %{project: project} do
    entries = [{1, 1}, {2, 2}, {3, 3}]
    write_entries(project, First, entries)
    write_entries(project, IncrementValue, entries)

    assert {:ok, table_name, :stale} = Schema.load(project, [First, IncrementValue])

    new_contents = table_contents(table_name)

    assert {1, 2} in new_contents
    assert {2, 3} in new_contents
    assert {3, 4} in new_contents
    assert length(new_contents) == 3

    refute File.exists?(Schema.index_file_path(project, First))
    assert File.exists?(Schema.index_file_path(project, IncrementValue))
  end

  test "migrations will be reapplied", %{project: project} do
    entries = [{1, 1}, {2, 2}, {3, 3}]
    write_entries(project, First, entries)
    write_entries(project, IncrementValue, entries)

    assert {:ok, table_name, :stale} = Schema.load(project, [First, IncrementValue, IncrementKey])
    new_contents = table_contents(table_name)

    assert {2, 2} in new_contents
    assert {3, 3} in new_contents
    assert {4, 4} in new_contents
    assert length(new_contents) == 3

    refute File.exists?(Schema.index_file_path(project, First))
    refute File.exists?(Schema.index_file_path(project, IncrementValue))
  end

  test "migrations can delete all entries", %{project: project} do
    defmodule Blank do
      use Schema, version: 2

      def migrate(_) do
        {:ok, []}
      end
    end

    entries = [{1, 1}, {2, 2}, {3, 3}]
    write_entries(project, First, entries)

    assert {:ok, table_name, :empty} = Schema.load(project, [First, Blank])

    assert table_contents(table_name) == []
  end

  test "failed migrations fail load", %{project: project} do
    defmodule FailedMigration do
      use Schema, version: 2

      def migrate(_) do
        {:error, :migration_failed}
      end
    end

    entries = [{1, 1}]
    write_entries(project, First, entries)
    assert {:error, :migration_failed} = Schema.load(project, [First, FailedMigration])
  end

  test "loading from a table with a different name that shares the filename", %{project: project} do
    defmodule StrangeName do
      def table_name do
        :strange
      end

      def index_file_name do
        First.index_file_name()
      end
    end

    entries = [{1, 1}, {2, 2}]
    write_entries(project, StrangeName, entries)
    {:ok, table_name, :stale} = Schema.load(project, [First])
    assert table_name == First.table_name()
    assert table_contents(table_name) == entries
    refute table_exists?(StrangeName.table_name())
  end

  defp table_exists?(table_name) do
    :ets.whereis(table_name) != :undefined
  end

  def destroy_index_path(%Project{} = project) do
    File.rm_rf(Schema.index_root(project))
  end

  def write_entries(project, schema_module, entries) do
    File.mkdir_p(Schema.index_root(project))
    table_name = schema_module.table_name()

    path_charlist =
      project
      |> Schema.index_file_path(schema_module)
      |> String.to_charlist()

    :ets.new(table_name, [:named_table, :set])
    :ets.insert(table_name, entries)
    :ok = :ets.tab2file(table_name, path_charlist)
    :ets.delete(table_name)
  end

  defp table_contents(table) do
    table
    |> :ets.tab2list()
    |> Enum.sort()
  end
end
