defmodule Lexical.RemoteControl.Search.IndexerTest do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer

  use ExUnit.Case
  use Patch
  import Lexical.Test.Fixtures

  defmodule FakeBackend do
    def set_entries(entries) do
      :persistent_term.put({__MODULE__, :entries}, entries)
    end

    def reduce(accumulator, reducer_fun) do
      {__MODULE__, :entries}
      |> :persistent_term.get([])
      |> Enum.reduce(accumulator, fn
        %{id: id} = entry, acc when is_integer(id) -> reducer_fun.(entry, acc)
        _, acc -> acc
      end)
    end
  end

  setup do
    project = project()
    start_supervised(Lexical.RemoteControl.Dispatch)
    {:ok, project: project}
  end

  describe "create_index/1" do
    test "returns a list of entries", %{project: project} do
      assert {:ok, entries} = Indexer.create_index(project)
      project_root = Project.root_path(project)

      assert length(entries) > 0
      assert Enum.all?(entries, fn entry -> String.starts_with?(entry.path, project_root) end)
    end

    test "entries are either .ex or .exs files", %{project: project} do
      assert {:ok, entries} = Indexer.create_index(project)
      assert Enum.all?(entries, fn entry -> Path.extname(entry.path) in [".ex", ".exs"] end)
    end
  end

  @ephemeral_file_name "ephemeral.ex"

  def with_an_ephemeral_file(%{project: project}) do
    file_path = Path.join([Project.root_path(project), "lib", @ephemeral_file_name])
    file_contents = ~s[
      defmodule Ephemeral do
      end
    ]
    File.write!(file_path, file_contents)

    on_exit(fn ->
      File.rm(file_path)
    end)

    {:ok, file_path: file_path}
  end

  def with_an_existing_index(%{project: project}) do
    {:ok, entries} = Indexer.create_index(project)
    FakeBackend.set_entries(entries)
    {:ok, entries: entries}
  end

  describe "update_index/2 encounters a new file" do
    setup [:with_an_existing_index, :with_an_ephemeral_file]

    test "the ephemeral file is not previously present in the index", %{entries: entries} do
      refute Enum.any?(entries, fn entry -> Path.basename(entry.path) == @ephemeral_file_name end)
    end

    test "the ephemeral file is listed in the updated index", %{project: project} do
      {:ok, [_structure, updated_entry], []} = Indexer.update_index(project, FakeBackend)
      assert Path.basename(updated_entry.path) == @ephemeral_file_name
      assert updated_entry.subject == Ephemeral
    end
  end

  describe "update_index/2" do
    setup [:with_an_ephemeral_file, :with_an_existing_index]

    test "sees the ephemeral file", %{entries: entries} do
      assert Enum.any?(entries, fn entry -> Path.basename(entry.path) == @ephemeral_file_name end)
    end

    test "returns the file paths of deleted files", %{project: project, file_path: file_path} do
      File.rm(file_path)
      assert {:ok, [], [^file_path]} = Indexer.update_index(project, FakeBackend)
    end

    test "updates files that have changed since the last index", %{
      project: project,
      entries: entries,
      file_path: file_path
    } do
      path_to_mtime = Map.new(entries, & &1.updated_at)
      [entry | _] = entries
      {{year, month, day}, hms} = entry.updated_at
      old_mtime = {{year - 1, month, day}, hms}

      patch(Indexer, :stat, fn path ->
        {ymd, {hour, minute, second}} =
          Map.get_lazy(path_to_mtime, file_path, &:calendar.universal_time/0)

        mtime =
          if path == file_path do
            {ymd, {hour, minute, second + 1}}
          else
            old_mtime
          end

        {:ok, %File.Stat{mtime: mtime}}
      end)

      new_contents = ~s[
        defmodule Brand.Spanking.New do
        end
      ]

      File.write!(file_path, new_contents)

      assert {:ok, [_structure, entry], []} = Indexer.update_index(project, FakeBackend)
      assert entry.path == file_path
      assert entry.subject == Brand.Spanking.New
    end
  end
end
