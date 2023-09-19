defmodule Lexical.RemoteControl.Search.Store.State do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Fuzzy

  require Logger

  defstruct [
    :project,
    :backend,
    :create_index,
    :update_index,
    :loaded?,
    :fuzzy,
    :async_load_ref
  ]

  def new(%Project{} = project, create_index, update_index, backend) do
    %__MODULE__{
      backend: backend,
      create_index: create_index,
      project: project,
      loaded?: false,
      update_index: update_index
    }
  end

  def drop(%__MODULE__{} = state) do
    state.backend.drop()
  end

  def destroy(%__MODULE__{} = state) do
    state.backend.destroy(state)
  end

  @doc """
  Asynchronously loads the search state.

  This function returns prior to creating or refreshing the index, which
  occurs in a separate process. The caller should listen for a message
  of the shape `{ref, result}`, where `ref` matches the state's
  `:async_load_ref`. Once received, that result should be passed to
  `async_load_complete/2`.
  """
  def async_load(%__MODULE__{loaded?: false, async_load_ref: nil} = state) do
    {:ok, backend_result} = state.backend.new(state.project)
    prepare_backend_async(state, backend_result)
  end

  def async_load(%__MODULE__{} = state) do
    {:ok, state}
  end

  def async_load_complete(%__MODULE__{} = state, result) do
    new_state = %__MODULE__{state | loaded?: true, async_load_ref: nil}

    case result do
      {:create_index, result} ->
        create_index_complete(new_state, result)

      {:update_index, result} ->
        update_index_complete(new_state, result)
    end
  end

  def replace(%__MODULE__{} = state, entries) do
    with :ok <- state.backend.replace_all(entries),
         :ok <- maybe_sync(state) do
      {:ok, %__MODULE__{state | fuzzy: Fuzzy.from_entries(entries)}}
    end
  end

  def exact(%__MODULE__{} = state, subject, constraints) do
    type = Keyword.get(constraints, :type, :_)
    subtype = Keyword.get(constraints, :subtype, :_)
    results = state.backend.find_by_subject(subject, type, subtype)
    {:ok, results}
  end

  def fuzzy(%__MODULE__{} = state, subject, constraints) do
    case Fuzzy.match(state.fuzzy, subject) do
      [] ->
        {:ok, []}

      refs ->
        type = Keyword.get(constraints, :type, :_)
        subtype = Keyword.get(constraints, :subtype, :_)
        {:ok, state.backend.find_by_refs(refs, type, subtype)}
    end
  end

  def all(%__MODULE__{} = state) do
    state.backend.select_all()
  end

  def update(%__MODULE__{} = state, path, entries) do
    with {:ok, state} <- update_nosync(state, path, entries),
         :ok <- maybe_sync(state) do
      {:ok, state}
    end
  end

  def update_nosync(%__MODULE__{} = state, path, entries) do
    with {:ok, deleted_refs} <- state.backend.delete_by_path(path),
         :ok <- state.backend.insert(entries) do
      fuzzy =
        state.fuzzy
        |> Fuzzy.drop_values(deleted_refs)
        |> Fuzzy.add(entries)

      {:ok, %__MODULE__{state | fuzzy: fuzzy}}
    end
  end

  require Logger

  defp prepare_backend_async(%__MODULE__{async_load_ref: nil} = state, backend_result) do
    task =
      Task.async(fn ->
        case state.backend.prepare(backend_result) do
          {:ok, :empty} ->
            Logger.info("backend reports empty")
            {:create_index, state.create_index.(state.project)}

          {:ok, :stale} ->
            Logger.info("backend reports stale")
            {:update_index, state.update_index.(state.project, all(state))}

          error ->
            Logger.error("Could not initialize index due to #{inspect(error)}")
            error
        end
      end)

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

  defp update_index_complete(%__MODULE__{} = state, {:ok, updated_entries, deleted_paths}) do
    fuzzy =
      state
      |> all()
      |> Fuzzy.from_entries()

    starting_state = %__MODULE__{state | fuzzy: fuzzy, loaded?: true}

    new_state =
      updated_entries
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

  defp maybe_sync(%__MODULE__{} = state) do
    if function_exported?(state.backend, :sync, 1) do
      state.backend.sync(state.project)
    else
      :ok
    end
  end
end
