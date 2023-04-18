defmodule Lexical.SourceFile.Store do
  @moduledoc """
  A backing store for source file documents

  This implementation stores documents in ETS, and partitions read and write operations. Read operations are served
  immediately by querying the ETS table, while writes go through a GenServer process (which is the owner of the ETS table).
  """
  defmodule State do
    alias Lexical.SourceFile
    alias Lexical.SourceFile.Store
    require Logger

    defstruct temporary_open_refs: %{}

    @table_name SourceFile.Store

    @type t :: %__MODULE__{}
    def new do
      :ets.new(@table_name, [:named_table, :set, :protected, write_concurrency: true])

      %__MODULE__{}
    end

    @spec fetch(Store.uri()) :: {:ok, t()} | {:error, :not_open}
    def fetch(uri) do
      case ets_fetch(:any, uri) do
        {:ok, _} = success -> success
        :error -> {:error, :not_open}
      end
    end

    @spec save(t, Store.uri()) :: {:ok, t()} | {:error, :not_open}
    def save(%__MODULE__{} = store, uri) do
      case ets_fetch(:sources, uri) do
        {:ok, source_file} ->
          source_file = SourceFile.mark_clean(source_file)
          ets_put(:sources, uri, source_file)
          {:ok, store}

        :error ->
          {:error, :not_open}
      end
    end

    @spec open(t, Store.uri(), String.t(), pos_integer()) :: {:ok, t} | {:error, :already_open}
    def open(%__MODULE__{} = store, uri, text, version) do
      case ets_fetch(:sources, uri) do
        {:ok, _} ->
          {:error, :already_open}

        :error ->
          source_file = SourceFile.new(uri, text, version)
          ets_put(:sources, uri, source_file)
          {:ok, store}
      end
    end

    def open?(uri) do
      ets_has_key?(:any, uri)
    end

    def close(%__MODULE__{} = store, uri) do
      case ets_pop(:sources, uri) do
        nil ->
          {:error, :not_open}

        _source_file ->
          {:ok, store}
      end
    end

    def get_and_update(%__MODULE__{} = store, uri, updater_fn) do
      with {:ok, source_file} <- fetch(uri),
           {:ok, updated_source} <- updater_fn.(source_file) do
        ets_put(:sources, uri, updated_source)

        {:ok, updated_source, store}
      else
        error ->
          normalize_error(error)
      end
    end

    def update(%__MODULE__{} = store, uri, updater_fn) do
      with {:ok, _, new_store} <- get_and_update(store, uri, updater_fn) do
        {:ok, new_store}
      end
    end

    def open_temporarily(%__MODULE__{} = store, path_or_uri, timeout) do
      uri = SourceFile.Path.ensure_uri(path_or_uri)
      path = SourceFile.Path.ensure_path(path_or_uri)

      with {:ok, contents} <- File.read(path) do
        source_file = SourceFile.new(uri, contents, 0)
        ref = schedule_unload(uri, timeout)

        new_refs =
          store
          |> maybe_cancel_old_ref(uri)
          |> Map.put(uri, ref)

        ets_put(:temp, uri, source_file)
        new_store = %__MODULE__{store | temporary_open_refs: new_refs}

        {:ok, source_file, new_store}
      end
    end

    def extend_timeout(%__MODULE__{} = store, uri, timeout) do
      case store.temporary_open_refs do
        %{^uri => ref} ->
          Process.cancel_timer(ref)
          new_ref = schedule_unload(uri, timeout)
          new_open_refs = Map.put(store.temporary_open_refs, uri, new_ref)
          %__MODULE__{store | temporary_open_refs: new_open_refs}

        _ ->
          store
      end
    end

    def unload(%__MODULE__{} = store, uri) do
      new_refs = Map.delete(store.temporary_open_refs, uri)
      ets_delete(:temp, uri)
      %__MODULE__{store | temporary_open_refs: new_refs}
    end

    defp maybe_cancel_old_ref(%__MODULE__{} = store, uri) do
      {_, new_refs} =
        Map.get_and_update(store.temporary_open_refs, uri, fn
          nil ->
            :pop

          old_ref when is_reference(old_ref) ->
            Process.cancel_timer(old_ref)
            :pop
        end)

      new_refs
    end

    defp schedule_unload(uri, timeout) do
      Process.send_after(self(), {:unload, uri}, timeout)
    end

    defp normalize_error(:error), do: {:error, :not_open}
    defp normalize_error(e), do: e

    @read_types [:sources, :temp, :any]
    @write_types [:sources, :temp]
    defp ets_fetch(type, key) when type in @read_types do
      case :ets.match(@table_name, {key, type_selector(type), :"$1"}) do
        [[value]] -> {:ok, value}
        _ -> :error
      end
    end

    defp ets_put(type, key, value) when type in @write_types do
      :ets.insert(@table_name, {key, type, value})
      :ok
    end

    defp ets_has_key?(type, key) when type in @read_types do
      match_spec = {key, type_selector(type), :"$1"}

      case :ets.match(@table_name, match_spec) do
        [] -> false
        _ -> true
      end
    end

    defp ets_pop(type, key) when type in @write_types do
      with {:ok, value} <- ets_fetch(type, key),
           :ok <- ets_delete(type, key) do
        value
      else
        _ ->
          nil
      end
    end

    defp ets_delete(type, key) when type in @write_types do
      match_spec = {key, type_selector(type), :_}
      :ets.match_delete(@table_name, match_spec)
      :ok
    end

    defp type_selector(:any), do: :_
    defp type_selector(type), do: type
  end

  alias Lexical.ProcessCache
  alias Lexical.SourceFile

  @type t :: %State{}

  @type uri :: String.t()
  @type updater :: (SourceFile.t() -> {:ok, SourceFile.t()} | {:error, any()})

  use GenServer

  @spec fetch(uri()) :: {:ok, SourceFile.t()} | :error
  def fetch(uri) do
    State.fetch(uri)
  end

  @spec save(uri()) :: :ok | {:error, :not_open}
  def save(uri) do
    GenServer.call(__MODULE__, {:save, uri})
  end

  @spec open?(uri()) :: boolean()
  def open?(uri) do
    State.open?(uri)
  end

  @spec open(uri(), String.t(), pos_integer()) :: :ok | {:error, :already_open}
  def open(uri, text, version) do
    GenServer.call(__MODULE__, {:open, uri, text, version})
  end

  def open_temporary(uri, timeout \\ 5000) do
    ProcessCache.trans(uri, 50, fn ->
      GenServer.call(__MODULE__, {:open_temporarily, uri, timeout})
    end)
  end

  @spec close(uri()) :: :ok | {:error, :not_open}
  def close(uri) do
    GenServer.call(__MODULE__, {:close, uri})
  end

  @spec get_and_update(uri(), updater()) :: {:ok, SourceFile.t()} | {:error, any()}
  def get_and_update(uri, update_fn) do
    GenServer.call(__MODULE__, {:get_and_update, uri, update_fn})
  end

  @spec update(uri(), updater()) :: :ok | {:error, any()}
  def update(uri, update_fn) do
    GenServer.call(__MODULE__, {:update, uri, update_fn})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, State.new()}
  end

  def handle_call({:save, uri}, _from, %State{} = state) do
    {reply, new_state} =
      case State.save(state, uri) do
        {:ok, _} = success -> success
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:open, uri, text, version}, _from, %State{} = state) do
    {reply, new_state} =
      case State.open(state, uri, text, version) do
        {:ok, _} = success -> success
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:open_temporarily, uri, timeout_ms}, _, %State{} = state) do
    {reply, new_state} =
      with {:error, :not_open} <- State.fetch(uri),
           {:ok, source_file, new_state} <- State.open_temporarily(state, uri, timeout_ms) do
        {{:ok, source_file}, new_state}
      else
        {:ok, source_file} ->
          new_state = State.extend_timeout(state, uri, timeout_ms)
          {{:ok, source_file}, new_state}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:close, uri}, _from, %State{} = state) do
    {reply, new_state} =
      case State.close(state, uri) do
        {:ok, _} = success -> success
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:get_and_update, uri, update_fn}, _from, %State{} = state) do
    {reply, new_state} =
      case State.get_and_update(state, uri, update_fn) do
        {:ok, updated_source, new_state} -> {{:ok, updated_source}, new_state}
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:update, uri, updater_fn}, _, %State{} = state) do
    {reply, new_state} =
      case State.update(state, uri, updater_fn) do
        {:ok, _} = success -> success
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_info({:unload, uri}, %State{} = state) do
    {:noreply, State.unload(state, uri)}
  end
end
