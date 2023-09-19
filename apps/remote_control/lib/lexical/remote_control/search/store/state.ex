defmodule Lexical.RemoteControl.Search.Store.State do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Fuzzy
  alias Lexical.RemoteControl.Search.Store.Ets
  require Logger

  @index_path Path.join("indexes", "source.index.ets")

  defstruct [
    :project,
    :index_path,
    :create_index,
    :update_index,
    :loaded?,
    :fuzzy,
    :ets_table,
    :async_load_ref
  ]

  def new(%Project{} = project, create_index, update_index) do
    %__MODULE__{
      create_index: create_index,
      project: project,
      index_path: index_path(project),
      loaded?: false,
      update_index: update_index
    }
    |> ensure_index_directory_exists()
  end

  def drop(%__MODULE__{}) do
    Ets.drop()
  end

  def metadata(%__MODULE__{loaded?: true} = state) do
    {:ok, Ets.find_metadata(), state}
  end

  def metadata(%__MODULE__{}) do
    {:error, :not_loaded}
  end

  def unique_fields(%__MODULE__{loaded?: true} = state, fields) do
    {:ok, Ets.select_unique_fields(fields), state}
  end

  def unique_fields(%__MODULE__{}, _fields) do
    {:error, :not_loaded}
  end

  def async_load(%__MODULE__{loaded?: false, async_load_ref: nil} = state) do
    case Ets.new(state.index_path) do
      {:ok, :empty, table_name} ->
        new_state = %__MODULE__{state | ets_table: table_name}
        create_index_async(new_state)

      {:ok, :stale, table_name} ->
        new_state = %__MODULE__{state | ets_table: table_name}
        update_index_async(new_state)

      error ->
        Logger.error("Could not initialize index due to #{inspect(error)}")
        error
    end
  end

  def async_load(%__MODULE__{} = state) do
    {:ok, state}
  end

  def async_load_complete(%__MODULE__{} = state, result) do
    new_state = Map.merge(state, %{loaded?: true, async_load_ref: nil})

    case result do
      {:create_index, result} ->
        create_index_complete(new_state, result)

      {:update_index, result} ->
        update_index_complete(new_state, result)
    end
  end

  def index_path(%Project{} = project) do
    Project.workspace_path(project, @index_path)
  end

  def replace(%__MODULE__{} = state, entries) do
    with :ok <- Ets.replace_all(entries),
         :ok <- Ets.sync_to(state.index_path) do
      {:ok, %__MODULE__{state | fuzzy: Fuzzy.from_entries(entries)}}
    else
      _ ->
        {:error, state}
    end
  end

  def exact(%__MODULE__{}, subject, constraints) do
    type = Keyword.get(constraints, :type, :_)
    subtype = Keyword.get(constraints, :subtype, :_)
    results = Ets.find_by_subject(subject, type, subtype)
    {:ok, results}
  end

  def fuzzy(%__MODULE__{} = state, subject, constraints) do
    case Fuzzy.match(state.fuzzy, subject) do
      [] ->
        {:ok, []}

      refs ->
        type = Keyword.get(constraints, :type, :_)
        subtype = Keyword.get(constraints, :subtype, :_)
        {:ok, Ets.find_by_references(refs, type, subtype)}
    end
  end

  def all(%__MODULE__{}) do
    Ets.select_all()
  end

  def update(%__MODULE__{} = state, path, entries) do
    with {:ok, state} <- update_nosync(state, path, entries),
         :ok <- Ets.sync_to(state.index_path) do
      {:ok, state}
    end
  end

  def update_nosync(%__MODULE__{} = state, path, entries) do
    with {:ok, deleted_entries} <- Ets.delete_by_path(path),
         :ok <- Ets.insert(entries) do
      refs_to_drop = Enum.map(deleted_entries, & &1.ref)
      fuzzy = state.fuzzy

      fuzzy =
        fuzzy
        |> Fuzzy.drop_values(refs_to_drop)
        |> Fuzzy.add(entries)

      {:ok, %__MODULE__{state | fuzzy: fuzzy}}
    end
  end

  defp ensure_index_directory_exists(%__MODULE__{} = state) do
    dir_name = Path.dirname(state.index_path)
    File.mkdir_p!(dir_name)
    state
  end

  defp create_index_async(%__MODULE__{async_load_ref: nil} = state) do
    task = Task.async(fn -> {:create_index, state.create_index.(state.project)} end)
    %__MODULE__{state | async_load_ref: task.ref}
  end

  defp create_index_complete(%__MODULE__{} = state, {:ok, entries}) do
    case replace(state, entries) do
      {:ok, state} ->
        state

      {:error, _} ->
        Logger.warning("Could not replace entries")
        state
    end
  end

  defp create_index_complete(%__MODULE__{} = state, {:error, _} = error) do
    Logger.warning("Could not create index, got: #{inspect(error)}")
    state
  end

  defp update_index_async(%__MODULE__{async_load_ref: nil} = state) do
    task = Task.async(fn -> {:update_index, state.update_index.(state.project, all(state))} end)
    %__MODULE__{state | async_load_ref: task.ref}
  end

  defp update_index_complete(%__MODULE__{} = state, {:ok, entries, deleted_paths}) do
    fuzzy = Fuzzy.from_entries(entries)
    starting_state = %__MODULE__{state | fuzzy: fuzzy, loaded?: true}

    new_state =
      entries
      |> Enum.group_by(& &1.path)
      |> Enum.reduce(starting_state, fn {path, entry_list}, state ->
        {:ok, new_state} = update_nosync(state, path, entry_list)
        new_state
      end)

    Enum.reduce(deleted_paths, new_state, fn path, state ->
      {:ok, new_state} = update_nosync(state, path, [])
      new_state
    end)
  end

  defp update_index_complete(%__MODULE__{} = state, {:error, _} = error) do
    Logger.warning("Could not update index, got: #{inspect(error)}")
    state
  end
end
