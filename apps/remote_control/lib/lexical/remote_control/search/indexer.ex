defmodule Lexical.RemoteControl.Search.Indexer do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer

  @indexable_extensions "*.{ex,exs}"

  def create_index(%Project{} = project) do
    entries =
      project
      |> indexable_files()
      |> async_chunks(&index_path/1)
      |> List.flatten()

    {:ok, entries}
  end

  def update_index(%Project{} = project, existing_entries) do
    path_to_last_index_at =
      existing_entries
      |> Enum.group_by(& &1.path, & &1.updated_at)
      |> Map.new(fn {k, v} -> {k, Enum.max(v)} end)

    project_files =
      project
      |> indexable_files
      |> MapSet.new()

    previously_indexed_paths = MapSet.new(path_to_last_index_at, fn {path, _} -> path end)

    new_paths = MapSet.difference(project_files, previously_indexed_paths)

    {paths_to_examine, paths_to_delete} =
      Enum.split_with(path_to_last_index_at, fn {path, _} -> File.regular?(path) end)

    changed_paths =
      for {path, updated_at_timestamp} <- paths_to_examine,
          newer_than?(path, updated_at_timestamp) do
        path
      end

    paths_to_delete = Enum.map(paths_to_delete, &elem(&1, 0))

    paths_to_reindex = changed_paths ++ Enum.to_list(new_paths)

    entries =
      paths_to_reindex
      |> async_chunks(&index_path/1)
      |> List.flatten()

    {:ok, entries, paths_to_delete}
  end

  defp index_path(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, entries} <- Indexer.Source.index(path, contents) do
      entries
    else
      _ ->
        []
    end
  end

  # Note: I tried doing something very similar using
  # Task.async_stream, but it was barely faster than just
  # doing things with Enum (16s vs 20s on my M2 max). This
  # function takes around 4 seconds to reindex all Lexical's
  # modules, making it 5x faster than Enum and 4x faster than
  # Task.async_stream
  defp async_chunks(data, processor, timeout \\ :infinity) do
    data
    |> Stream.chunk_every(System.schedulers_online())
    |> Enum.map(fn chunk ->
      Task.async(fn -> Enum.map(chunk, processor) end)
    end)
    |> Task.await_many(timeout)
  end

  defp newer_than?(path, timestamp) do
    case stat(path) do
      {:ok, %File.Stat{} = stat} ->
        stat.mtime > timestamp

      _ ->
        false
    end
  end

  def indexable_files(%Project{} = project) do
    root_dir = Project.root_path(project)

    [root_dir, "**", @indexable_extensions]
    |> Path.join()
    |> Path.wildcard()
  end

  # stat(path) is here for testing so it can be mocked
  defp stat(path) do
    File.stat(path)
  end
end
