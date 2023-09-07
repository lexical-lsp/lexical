defmodule Lexical.RemoteControl.Search.IndexerTest do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer

  use ExUnit.Case
  use Patch
  import Lexical.Test.Fixtures

  setup do
    project = project()
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
    {:ok, entries: entries}
  end

  describe "update_index/2 encounters a new file" do
    setup [:with_an_existing_index, :with_an_ephemeral_file]

    test "the ephemeral file is not previously present in the index", %{entries: entries} do
      refute Enum.any?(entries, fn entry -> Path.basename(entry.path) == @ephemeral_file_name end)
    end

    test "the ephemeral file is listed in the updated index", %{
      project: project,
      entries: entries
    } do
      {:ok, [updated_entry], []} = Indexer.update_index(project, entries)
      assert Path.basename(updated_entry.path) == @ephemeral_file_name
      assert updated_entry.subject == Ephemeral
    end
  end

  describe "update_index/2" do
    setup [:with_an_ephemeral_file, :with_an_existing_index]

    test "sees the ephemeral file", %{entries: entries} do
      assert Enum.any?(entries, fn entry -> Path.basename(entry.path) == @ephemeral_file_name end)
    end

    test "returns the file paths of deleted files", %{
      project: project,
      entries: entries,
      file_path: file_path
    } do
      File.rm(file_path)
      assert {:ok, [], [^file_path]} = Indexer.update_index(project, entries)
    end

    test "updates files that have changed since the last index", %{
      project: project,
      entries: entries,
      file_path: file_path
    } do
      path_to_mtime =
        Map.new(entries, fn entry ->
          {:ok, updated_at} = DateTime.from_unix(entry.updated_at, :millisecond)

          ymd = {updated_at.year, updated_at.month, updated_at.day}
          hms = {updated_at.hour, updated_at.minute, updated_at.second}

          {entry.path, {ymd, hms}}
        end)

      new_contents = ~s[
        defmodule Brand.Spanking.New do
        end
      ]

      patch(Indexer, :stat, fn path ->
        {ymd, {hour, minute, second}} = Map.get(path_to_mtime, file_path, &:calendar.local_time/0)

        hms =
          if path == file_path do
            {hour, minute, second + 1}
          else
            {hour, minute, second}
          end

        mtime = {ymd, hms}

        {:ok, %File.Stat{mtime: mtime}}
      end)

      File.write!(file_path, new_contents)

      assert {:ok, [entry], []} = Indexer.update_index(project, entries)
      assert entry.path == file_path
      assert entry.subject == Brand.Spanking.New
    end
  end
end
