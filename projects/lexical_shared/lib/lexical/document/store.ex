defmodule Lexical.Document.Store do
  @moduledoc """
  Backing store for source file documents.
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
  @type start_opt :: {:derive, derivations}

  defmodule State do
    @moduledoc false

    alias Lexical.Document
    alias Lexical.Document.Store

    require Logger

    defstruct documents: %{}, temporary_open_refs: %{}, derivations: %{}

    @type t :: %__MODULE__{}

    def new(opts \\ []) do
      [derive: derivations] =
        opts
        |> Keyword.validate!(derive: [])
        |> Keyword.take([:derive])

      %__MODULE__{derivations: Map.new(derivations)}
    end

    @spec fetch(t, Lexical.uri()) :: {:ok, Document.t(), t} | {:error, :not_open}
    def fetch(%__MODULE__{} = store, uri) do
      case store.documents do
        %{^uri => {document, _}} -> {:ok, document, store}
        _ -> {:error, :not_open}
      end
    end

    @spec fetch(t, Lexical.uri(), Store.derivation_key()) ::
            {:ok, {Document.t(), Store.derived()}, t} | {:error, :not_open}
    def fetch(%__MODULE__{} = store, uri, key) do
      case store.documents do
        %{^uri => {document, %{^key => derived}}} ->
          {:ok, {document, derived}, store}

        %{^uri => {document, derivations}} ->
          derived = derive(store, key, document)
          derivations = Map.put(derivations, key, derived)
          store = put_document(store, document, derivations)
          {:ok, {document, derived}, store}

        _ ->
          {:error, :not_open}
      end
    end

    @spec save(t, Lexical.uri()) :: {:ok, t} | {:error, :not_open}
    def save(%__MODULE__{} = store, uri) do
      case store.documents do
        %{^uri => {document, derivations}} ->
          document = Document.mark_clean(document)
          store = put_document(store, document, derivations)
          {:ok, store}

        _ ->
          {:error, :not_open}
      end
    end

    @spec open(t, Lexical.uri(), String.t(), pos_integer()) :: {:ok, t} | {:error, :already_open}
    def open(%__MODULE__{temporary_open_refs: refs} = store, uri, text, version)
        when is_map_key(refs, uri) do
      {_, store} =
        store
        |> maybe_cancel_old_ref(uri)
        |> pop_document(uri)

      open(store, uri, text, version)
    end

    def open(%__MODULE__{} = store, uri, text, version) do
      case store.documents do
        %{^uri => _} ->
          {:error, :already_open}

        _ ->
          document = Document.new(uri, text, version)
          store = put_document(store, document)
          {:ok, store}
      end
    end

    @spec open?(t, Lexical.uri()) :: boolean
    def open?(%__MODULE__{} = store, uri) do
      Map.has_key?(store.documents, uri)
    end

    @spec close(t, Lexical.uri()) :: {:ok, t} | {:error, :not_open}
    def close(%__MODULE__{} = store, uri) do
      case pop_document(store, uri) do
        {nil, _} ->
          {:error, :not_open}

        {_, store} ->
          {:ok, maybe_cancel_old_ref(store, uri)}
      end
    end

    @spec get_and_update(t, Lexical.uri(), Store.updater()) ::
            {:ok, Document.t(), t} | {:error, any()}
    def get_and_update(%__MODULE__{} = store, uri, updater_fn) do
      with {:ok, {document, _derivations}} <- Map.fetch(store.documents, uri),
           {:ok, document} <- updater_fn.(document) do
        {:ok, document, put_document(store, document)}
      else
        error ->
          normalize_error(error)
      end
    end

    @spec update(t, Lexical.uri(), Store.updater()) :: {:ok, t} | {:error, any()}
    def update(%__MODULE__{} = store, uri, updater_fn) do
      with {:ok, _, store} <- get_and_update(store, uri, updater_fn) do
        {:ok, store}
      end
    end

    @spec open_temporarily(t, Lexical.uri() | Path.t(), timeout()) ::
            {:ok, Document.t(), t} | {:error, term()}
    def open_temporarily(%__MODULE__{} = store, path_or_uri, timeout) do
      uri = Document.Path.ensure_uri(path_or_uri)
      path = Document.Path.ensure_path(path_or_uri)

      with {:ok, contents} <- File.read(path) do
        document = Document.new(uri, contents, 0)
        ref = schedule_unload(uri, timeout)

        new_store =
          store
          |> maybe_cancel_old_ref(uri)
          |> put_ref(uri, ref)
          |> put_document(document)

        {:ok, document, new_store}
      end
    end

    @spec extend_timeout(t, Lexical.uri(), timeout()) :: t
    def extend_timeout(%__MODULE__{} = store, uri, timeout) do
      case store.temporary_open_refs do
        %{^uri => ref} ->
          Process.cancel_timer(ref)
          new_ref = schedule_unload(uri, timeout)
          put_ref(store, uri, new_ref)

        _ ->
          store
      end
    end

    @spec unload(t, Lexical.uri()) :: t
    def unload(%__MODULE__{} = store, uri) do
      {_, store} = pop_document(store, uri)
      maybe_cancel_old_ref(store, uri)
    end

    defp put_document(%__MODULE__{} = store, %Document{} = document, derivations \\ %{}) do
      put_in(store.documents[document.uri], {document, derivations})
    end

    defp pop_document(%__MODULE__{} = store, uri) do
      case Map.pop(store.documents, uri) do
        {nil, _} -> {nil, store}
        {document, documents} -> {document, %__MODULE__{store | documents: documents}}
      end
    end

    defp put_ref(%__MODULE__{} = store, uri, ref) do
      put_in(store.temporary_open_refs[uri], ref)
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

      %__MODULE__{store | temporary_open_refs: new_refs}
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
    GenServer.call(name(), {:open?, uri})
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

  def handle_call({:open?, uri}, _from, %State{} = state) do
    reply = State.open?(state, uri)
    {:reply, reply, state}
  end

  def handle_call({:open_temporarily, uri, timeout_ms}, _, %State{} = state) do
    {reply, new_state} =
      with {:error, :not_open} <- State.fetch(state, uri),
           {:ok, document, new_state} <- State.open_temporarily(state, uri, timeout_ms) do
        {{:ok, document}, new_state}
      else
        {:ok, document, new_state} ->
          {{:ok, document}, State.extend_timeout(new_state, uri, timeout_ms)}

        error ->
          {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:fetch, uri}, _from, %State{} = state) do
    {reply, new_state} =
      case State.fetch(state, uri) do
        {:ok, value, new_state} -> {{:ok, value}, new_state}
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:fetch, uri, key}, _from, %State{} = state) do
    {reply, new_state} =
      case State.fetch(state, uri, key) do
        {:ok, value, new_state} -> {{:ok, value}, new_state}
        error -> {error, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:close, uri}, _from, %State{} = state) do
    {reply, new_state} =
      case State.close(state, uri) do
        {:ok, new_state} -> {:ok, new_state}
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
        {:ok, new_state} -> {:ok, new_state}
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
