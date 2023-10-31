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

  # 128 K blocks indexed lexical in 5.3 seconds
  @bytes_per_block 1024 * 128
  defp async_chunks(file_paths, processor, timeout \\ :infinity) do
    # this function tries to even out the amount of data processed by
    # async stream by making each chunk emitted by the initial stream to
    # be roughly equivalent

    initial_state = {0, []}

    chunk_fn = fn {path, file_size}, {block_size, paths} ->
      new_block_size = file_size + block_size
      new_paths = [path | paths]

      if new_block_size >= @bytes_per_block do
        {:cont, new_paths, initial_state}
      else
        {:cont, {new_block_size, new_paths}}
      end
    end

    after_fn = fn
      {_, []} ->
        {:cont, []}

      {_, paths} ->
        {:cont, paths, []}
    end

    # Shuffling the results helps speed in some projects, as larger files tend to clump
    # together, like when there are auto-generated elixir modules.
    file_paths
    |> path_to_sizes()
    |> Enum.shuffle()
    |> Stream.chunk_while(initial_state, chunk_fn, after_fn)
    |> Task.async_stream(&Enum.map(&1, processor), timeout: timeout)
    |> Enum.flat_map(fn
      {:ok, entry_chunks} -> entry_chunks
      _ -> []
    end)
  end

  defp path_to_sizes(paths) do
    Enum.reduce(paths, [], fn file_path, acc ->
      case File.stat(file_path) do
        {:ok, %File.Stat{} = stat} ->
          [{file_path, stat.size} | acc]

        _ ->
          acc
      end
    end)
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
    |> Path.wildcard(~r"^(?!.*(build|deps)).*$")
  end

  # stat(path) is here for testing so it can be mocked
  defp stat(path) do
    File.stat(path)
  end
end
