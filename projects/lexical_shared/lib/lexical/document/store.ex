defmodule Lexical.Document.Store do
  @moduledoc """
  An ETS backing store for source file documents.
  """

  alias Lexical.Document
  alias Lexical.ProcessCache

  use GenServer

  @type updater :: (Document.t() -> {:ok, Document.t()} | {:error, any()})

  @type derivations :: [derivation]
  @type derivation :: {derivation_key, derivation_fun}
  @type derivation_key :: atom()
  @type derivation_fun :: (Document.t() -> derived) | {module(), atom()}
  @type derived :: any()

  @type start_opts :: [start_opt]
  @type start_opt :: {:derivations, derivations}

  defmodule State do
    @moduledoc false

    alias Lexical.Document
    alias Lexical.Document.Store

    require Logger

    defstruct temporary_open_refs: %{}, derivations: %{}

    @type t :: %__MODULE__{}

    @table_name Document.Store

    def new(opts \\ []) do
      [derivations: derivations] =
        opts
        |> Keyword.validate!(derivations: [])
        |> Keyword.take([:derivations])

      :ets.new(@table_name, [:named_table, :set, :protected, read_concurrency: true])

      %__MODULE__{derivations: Map.new(derivations)}
    end

    @spec fetch(Lexical.uri()) :: {:ok, Document.t()} | {:error, :not_open}
    def fetch(uri) do
      case ets_fetch(uri, :any) do
        {:ok, {document, _}} -> {:ok, document}
        :error -> {:error, :not_open}
      end
    end

    @spec fetch(t, Lexical.uri(), Store.derivation_key()) ::
            {:ok, {Document.t(), Store.derived()}} | {:error, :not_open}
    def fetch(%__MODULE__{} = store, uri, derivation_key) do
      case ets_fetch(uri, :any, true) do
        {:ok, {_uri, _type, {document, %{^derivation_key => derived}}}} ->
          {:ok, {document, derived}}

        {:ok, {_uri, type, {document, derivations}}} ->
          derived = derive(store, derivation_key, document)
          derivations = Map.put(derivations, derivation_key, derived)
          ets_put(uri, type, {document, derivations})
          {:ok, {document, derived}}

        :error ->
          {:error, :not_open}
      end
    end

    @spec save(t, Lexical.uri()) :: {:ok, t()} | {:error, :not_open}
    def save(%__MODULE__{} = store, uri) do
      case ets_fetch(uri, :sources) do
        {:ok, {document, derivations}} ->
          document = Document.mark_clean(document)
          ets_put(uri, :sources, {document, derivations})
          {:ok, store}

        :error ->
          {:error, :not_open}
      end
    end

    @spec open(t, Lexical.uri(), String.t(), pos_integer()) :: {:ok, t} | {:error, :already_open}
    def open(%__MODULE__{} = store, uri, text, version) do
      case ets_fetch(uri, :sources) do
        {:ok, _} ->
          {:error, :already_open}

        :error ->
          document = Document.new(uri, text, version)
          ets_put(uri, :sources, {document, %{}})
          {:ok, store}
      end
    end

    @spec open?(Lexical.uri()) :: boolean
    def open?(uri) do
      ets_has_key?(uri, :any)
    end

    @spec close(Lexical.uri()) :: :ok | {:error, :not_open}
    def close(uri) do
      case ets_pop(uri, :sources) do
        nil -> {:error, :not_open}
        _value -> :ok
      end
    end

    def get_and_update(%__MODULE__{} = store, uri, updater_fn) do
      with {:ok, {document, _derivations}} <- ets_fetch(uri, :any),
           {:ok, updated_source} <- updater_fn.(document) do
        ets_put(uri, :sources, {updated_source, %{}})

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

    @spec open_temporarily(t(), Lexical.uri() | Path.t(), timeout()) ::
            {:ok, Document.t(), t()} | {:error, term()}
    def open_temporarily(%__MODULE__{} = store, path_or_uri, timeout) do
      uri = Document.Path.ensure_uri(path_or_uri)
      path = Document.Path.ensure_path(path_or_uri)

      with {:ok, contents} <- File.read(path) do
        document = Document.new(uri, contents, 0)
        ref = schedule_unload(uri, timeout)

        new_refs =
          store
          |> maybe_cancel_old_ref(uri)
          |> Map.put(uri, ref)

        ets_put(uri, :temp, {document, %{}})
        new_store = %__MODULE__{store | temporary_open_refs: new_refs}

        {:ok, document, new_store}
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
      ets_delete(uri, :temp)
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

    defp derive(%__MODULE__{} = store, key, document) do
      case store.derivations do
        %{^key => fun} when is_function(fun, 1) ->
          fun.(document)

        %{^key => {module, fun_name}} ->
          apply(module, fun_name, [document])

        _ ->
          known = Map.keys(store.derivations)

          raise ArgumentError,
                "No derivation for #{inspect(key)}, expected one of #{inspect(known)}"
      end
    end

    @read_types [:sources, :temp, :any]
    @write_types [:sources, :temp]

    defp ets_fetch(key, type, entire_object? \\ false)

    defp ets_fetch(key, type, false) when type in @read_types do
      case :ets.match(@table_name, {key, type_selector(type), :"$1"}) do
        [[value]] -> {:ok, value}
        _ -> :error
      end
    end

    defp ets_fetch(key, type, true) when type in @read_types do
      type = type_selector(type)
      match_spec = [{{key, type, :"$1"}, [], [:"$_"]}]

      case :ets.select(@table_name, match_spec) do
        [object] -> {:ok, object}
        _ -> :error
      end
    end

    defp ets_put(key, type, value) when type in @write_types do
      :ets.insert(@table_name, {key, type, value})
      :ok
    end

    defp ets_has_key?(key, type) when type in @read_types do
      pattern = {key, type_selector(type), :"$1"}

      case :ets.match(@table_name, pattern) do
        [] -> false
        _ -> true
      end
    end

    defp ets_pop(key, type) when type in @write_types do
      with {:ok, value} <- ets_fetch(key, type),
           :ok <- ets_delete(key, type) do
        value
      else
        _ ->
          nil
      end
    end

    defp ets_delete(key, type) when type in @write_types do
      pattern = {key, type, :_}
      :ets.match_delete(@table_name, pattern)
      :ok
    end

    defp type_selector(:any), do: :_
    defp type_selector(type), do: type
  end

  @spec fetch(Lexical.uri()) :: {:ok, Document.t()} | {:error, :not_open}
  def fetch(uri) do
    GenServer.call(name(), {:fetch, uri})
  end

  @spec fetch(Lexical.uri(), derivation_key) ::
          {:ok, {Document.t(), derived}} | {:error, :not_open}
  def fetch(uri, key) do
    GenServer.call(name(), {:fetch, uri, key})
  end

  @spec save(Lexical.uri()) :: :ok | {:error, :not_open}
  def save(uri) do
    GenServer.call(name(), {:save, uri})
  end

  @spec open?(Lexical.uri()) :: boolean()
  def open?(uri) do
    State.open?(uri)
  end

  @spec open(Lexical.uri(), String.t(), pos_integer()) :: :ok | {:error, :already_open}
  def open(uri, text, version) do
    GenServer.call(name(), {:open, uri, text, version})
  end

  @spec open_temporary(Lexical.uri() | Path.t()) ::
          {:ok, Document.t()} | {:error, term()}

  @spec open_temporary(Lexical.uri() | Path.t(), timeout()) ::
          {:ok, Document.t()} | {:error, term()}
  def open_temporary(uri, timeout \\ 5000) do
    ProcessCache.trans(uri, 50, fn ->
      GenServer.call(name(), {:open_temporarily, uri, timeout})
    end)
  end

  @spec close(Lexical.uri()) :: :ok | {:error, :not_open}
  def close(uri) do
    GenServer.call(name(), {:close, uri})
  end

  @spec get_and_update(Lexical.uri(), updater) :: {:ok, Document.t()} | {:error, any()}
  def get_and_update(uri, update_fn) do
    GenServer.call(name(), {:get_and_update, uri, update_fn})
  end

  @spec update(Lexical.uri(), updater) :: :ok | {:error, any()}
  def update(uri, update_fn) do
    GenServer.call(name(), {:update, uri, update_fn})
  end

  @spec start_link(start_opts) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name())
  end

  @impl GenServer
  def init(opts) do
    {:ok, State.new(opts)}
  end

  @impl GenServer
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
           {:ok, document, new_state} <- State.open_temporarily(state, uri, timeout_ms) do
        {{:ok, document}, new_state}
      else
        {:ok, document} ->
          new_state = State.extend_timeout(state, uri, timeout_ms)
          {{:ok, document}, new_state}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:fetch, uri}, _from, %State{} = state) do
    reply = State.fetch(uri)
    {:reply, reply, state}
  end

  def handle_call({:fetch, uri, key}, _from, %State{} = state) do
    reply = State.fetch(state, uri, key)
    {:reply, reply, state}
  end

  def handle_call({:close, uri}, _from, %State{} = state) do
    reply = State.close(uri)
    {:reply, reply, state}
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

  @impl GenServer
  def handle_info({:unload, uri}, %State{} = state) do
    {:noreply, State.unload(state, uri)}
  end

  def set_entropy(entropy) do
    :persistent_term.put(entropy_key(), entropy)
    entropy
  end

  def entropy do
    case :persistent_term.get(entropy_key(), :undefined) do
      :undefined ->
        [:positive]
        |> System.unique_integer()
        |> set_entropy()

      entropy ->
        entropy
    end
  end

  def name do
    {:via, :global, {__MODULE__, entropy()}}
  end

  defp entropy_key do
    {__MODULE__, :entropy}
  end
end
