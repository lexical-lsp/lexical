defmodule Lexical.RemoteControl.Search.Store.State do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Fuzzy
  alias Lexical.RemoteControl.Search.Store.Ets
  require Logger

  @index_path Path.join("indexes", "source.index.ets")

  defstruct [:project, :index_path, :create_index, :update_index, :loaded?, :fuzzy, :ets_table]

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

  def metadata(%__MODULE__{} = state) do
    with {:ok, state} <- load(state) do
      {:ok, Ets.table_metadata(), state}
    end
  end

  def unique_fields(%__MODULE__{} = state, fields) do
    with {:ok, state} <- load(state) do
      {:ok, Ets.select_unique_fields(fields), state}
    end
  end

  def load(%__MODULE__{loaded?: true} = state) do
    {:ok, state}
  end

  def load(%__MODULE__{} = state) do
    with :error <- load_from_file(state),
         {:error, _} = error <- reindex_and_load(state) do
      Logger.error("Could not initialize index due to #{inspect(error)}")
      {:ok, state}
    end
  end

  def index_path(%Project{} = project) do
    Project.workspace_path(project, @index_path)
  end

  def replace(%__MODULE__{} = state, entries) do
    with true <- Ets.replace_all(entries),
         :ok <- Ets.sync_to(state.index_path) do
      {:ok, %__MODULE__{state | fuzzy: Fuzzy.new(entries)}}
    else
      _ ->
        {:error, state}
    end
  end

  def exact(%__MODULE__{}, subject, constraints) do
    type = Keyword.get(constraints, :type, :_)
    subtype = Keyword.get(constraints, :subtype, :_)
    results = Ets.find_exact(subject, type, subtype)
    {:ok, results}
  end

  def fuzzy(%__MODULE__{} = state, subject, constraints) do
    case Fuzzy.match(state.fuzzy, subject) do
      [] ->
        {:ok, []}

      refs ->
        type = Keyword.get(constraints, :type, :_)
        subtype = Keyword.get(constraints, :subtype, :_)
        {:ok, Ets.find_by_ref(type, subtype, refs)}
    end
  end

  def all(%__MODULE__{}) do
    Ets.select_all()
  end

  def update(%__MODULE__{} = state, path, entries) do
    with {:ok, deleted_entries} <- Ets.delete_by_path(path),
         true <- Ets.insert(entries),
         :ok <- Ets.sync_to(state.index_path) do
      refs_to_drop = Enum.map(deleted_entries, & &1.ref)
      fuzzy = state.fuzzy

      fuzzy =
        fuzzy
        |> Fuzzy.drop_refs(refs_to_drop)
        |> Fuzzy.update(entries)

      {:ok, %__MODULE__{state | fuzzy: fuzzy}}
    end
  end

  defp ensure_index_directory_exists(%__MODULE__{} = state) do
    dir_name = Path.dirname(state.index_path)
    File.mkdir_p!(dir_name)
    state
  end

  defp load_from_file(%__MODULE__{} = state) do
    with :ok <- Ets.load_from(state.index_path),
         entries = all(state),
         {:ok, updated_entries, deleted_paths} <- state.update_index.(state.project, entries) do
      fuzzy = Fuzzy.new(entries)
      starting_state = %__MODULE__{state | fuzzy: fuzzy, loaded?: true}

      new_state =
        updated_entries
        |> Enum.group_by(& &1.path)
        |> Enum.reduce(starting_state, fn {path, entry_list}, state ->
          {:ok, new_state} = update(state, path, entry_list)
          new_state
        end)

      new_state =
        Enum.reduce(deleted_paths, new_state, fn path, state ->
          {:ok, new_state} = update(state, path, [])
          new_state
        end)

      {:ok, %__MODULE__{new_state | loaded?: true}}
    end
  end

  defp reindex_and_load(%__MODULE__{} = state) do
    table_name = Ets.new()

    with {:ok, entries} <- state.create_index.(state.project),
         {:ok, state} <- replace(state, entries) do
      {:ok, %__MODULE__{state | loaded?: true, fuzzy: Fuzzy.new(entries), ets_table: table_name}}
    end
  end
end
