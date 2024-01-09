defmodule Lexical.RemoteControl.Search.Store.Backends.Khepri do
  @moduledoc """
  A search backend that uses the khepri database
  """
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.Backend
  alias Lexical.RemoteControl.Search.Store.Backends.Khepri.Operations
  alias Lexical.VM.Versions

  require Logger

  @behaviour Backend

  @impl Backend
  def new(%Project{} = project) do
    project
    |> data_directory()
    |> :khepri.start(khepri_store_id(project))
  end

  @impl Backend
  def prepare(%Project{}, store_id) do
    if :khepri.exists(store_id, :khepri_path.from_binary("/entries")) do
      {:ok, :stale}
    else
      {:ok, :empty}
    end
  end

  @impl Backend
  def insert(_project, []) do
    :ok
  end

  def insert(%Project{} = project, entries) do
    operation = &Operations.tx_insert_many/1
    store_id = khepri_store_id(project)

    :khepri.transaction(store_id, operation, [entries])
    :ok
  end

  @impl Backend
  def drop(%Project{} = project) do
    store_id = khepri_store_id(project)

    case :khepri.delete_many(store_id, :khepri_path.from_binary("/**")) do
      :ok -> true
      _ -> false
    end
  end

  @impl Backend
  def destroy(%Project{} = project) do
    store_id = khepri_store_id(project)

    with :ok <- :khepri.reset(store_id, 5_000),
         {:ok, _} <- File.rm_rf(data_directory(project)) do
    end

    :ok
  end

  @impl Backend
  def select_all(%Project{} = project) do
    store_id = khepri_store_id(project)

    case :khepri.get_many(store_id, Operations.wildcard_path()) do
      {:ok, results} -> Map.values(results)
      _ -> []
    end
  end

  @impl Backend
  def replace_all(%Project{} = project, entries) do
    store_id = khepri_store_id(project)
    operation = &Operations.tx_replace_all/2

    :khepri.transaction(store_id, operation, [Operations.wildcard_path(), entries])
    :ok
    # :khepri.delete_many(store_id, everything)
    # insert(project, entries)
  end

  @impl Backend
  def delete_by_path(%Project{} = project, path) do
    store_id = khepri_store_id(project)
    path_pattern = Operations.to_path("*", "*", "*", path, "*")

    :khepri.transaction(store_id, fn ->
      with {:ok, results} <- :khepri_tx.get_many(path_pattern),
           :ok <- :khepri_tx.delete_many(path_pattern) do
        Map.values(results)
      end
    end)
  end

  @impl Backend
  def find_by_subject(%Project{} = project, subject_query, type_query, subtype_query) do
    store_id = khepri_store_id(project)

    subject_query = Operations.path_for(subject_query, &Operations.encode_subject/1)
    path_pattern = Operations.to_path(type_query, subtype_query, subject_query, "*", "*")

    case :khepri.get_many(store_id, path_pattern) do
      {:ok, entries} ->
        Map.values(entries)

      _ ->
        []
    end
  end

  @impl Backend
  def find_by_ids(%Project{} = project, id_list, type_query, subtype_query) do
    store_id = khepri_store_id(project)

    Enum.flat_map(id_list, fn id ->
      path_pattern = Operations.to_path(type_query, subtype_query, "*", "*", id)

      case :khepri.get_many(store_id, path_pattern) do
        {:ok, value} ->
          Map.values(value)

        _ ->
          []
      end
    end)
  end

  defp data_directory(%Project{} = project) do
    current = Versions.current()
    Project.workspace_path(project, ["indexes", "khepri", "v1", current.erlang, current.elixir])
  end

  defp khepri_store_id(%Project{} = project) do
    :"#{Project.name(project)}_khepri_store"
  end
end
