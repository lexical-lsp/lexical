defmodule Lexical.RemoteControl.Search.Store.Backends.Mnesia.Schema do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backends.Mnesia
  alias Lexical.RemoteControl.Search.Store.Backends.Mnesia.State
  alias Lexical.VM.Versions

  import Record

  @fields [:path, :ref, :value]

  defrecord :row, Mnesia, [:key | @fields]
  defrecord :row_pattern, Mnesia, Enum.map([:key | @fields], fn name -> {name, :_} end)

  # Schema manipulation functions
  def ensure_schema(%State{} = state) do
    mnesia_dir =
      state.project
      |> mnesia_dir()
      |> String.to_charlist()

    Application.put_env(:mnesia, :dir, mnesia_dir)
    State.rpc_call(state, Application, :put_env, [:mnesia, :dir, mnesia_dir])
    create_schema(state)
  end

  def wait_for_tables do
    :mnesia.wait_for_tables([Mnesia], :infinity)
  end

  def destroy(%Project{} = project) do
    data_dir = mnesia_dir(project)

    with :stopped <- :mnesia.stop(),
         {:ok, _} <- File.rm_rf(data_dir) do
      :ok
    end
  end

  def destroy(%State{} = state) do
    destroy(state.project)
  end

  def load_state do
    case :mnesia.table_info(Mnesia, :size) do
      0 -> :empty
      _ -> :stale
    end
  end

  def create_local_schema(%State{} = state) do
    with :ok <- ensure_local_schema(state) do
      create_local_ram_table_copies(state)
    end
  end

  def clean_old_ram_copies(%State{} = state) do
    if Mnesia.persist_to_disc?() do
      Mnesia
      |> :mnesia.table_info(:ram_copies)
      |> Enum.reject(&(&1 in [state.mnesia_node, Node.self()]))
      |> Enum.each(&:mnesia.del_table_copy(Mnesia, &1))
    end

    :ok
  end

  defp ensure_local_schema(%State{} = state) do
    case :mnesia.create_schema([Node.self()]) do
      :ok ->
        State.rpc_call(state, :mnesia, :change_config, [:extra_db_nodes, [Node.self()]])

      {:error, {node, {:already_exists, node}}} ->
        :ok
    end
  end

  def create_table(%State{} = state) do
    case State.rpc_call(state, :mnesia, :create_table, [Mnesia, table_options(state)]) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, Mnesia}} ->
        :ok

      error ->
        error
    end
  end

  def to_key(subject, type, subtype, elixir_version \\ nil, erlang_version \\ nil) do
    versions = Versions.current()
    elixir_version = elixir_version || versions.elixir
    erlang_version = erlang_version || versions.erlang
    {to_subject(subject), type, subtype, elixir_version, erlang_version}
  end

  def to_row(%Entry{} = entry) do
    entry_key =
      to_key(entry.subject, entry.type, entry.subtype, entry.elixir_version, entry.erlang_version)

    row(key: entry_key, path: entry.path, ref: entry.ref, value: entry)
  end

  # Private
  defp to_subject(binary) when is_binary(binary), do: binary
  defp to_subject(:_), do: :_
  defp to_subject(other), do: inspect(other)

  defp create_schema(%State{} = state) do
    mnesia_node = state.mnesia_node

    case State.rpc_call(state, :mnesia, :create_schema, [[state.mnesia_node]]) do
      :ok ->
        :ok

      {:error, {^mnesia_node, {:already_exists, ^mnesia_node}}} ->
        :ok

      other_error ->
        other_error
    end
  end

  defp create_local_ram_table_copies(%State{} = state) do
    if Mnesia.persist_to_disc?() and Node.self() not in existing_ram_table_copies(state) do
      do_create_local_ram_table_copies(state)
    else
      :ok
    end
  end

  defp do_create_local_ram_table_copies(%State{} = state) do
    case State.rpc_call(state, :mnesia, :add_table_copy, [Mnesia, Node.self(), :ram_copies]) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, _, _}} ->
        :ok

      error ->
        error
    end
  end

  defp existing_ram_table_copies(%State{} = state) do
    case State.rpc_call(state, :mnesia, :table_info, [Mnesia, :ram_copies]) do
      {:badrpc, {:EXIT, {:aborted, {:no_exists, Mnesia, :ram_copies}}}} ->
        []

      list when is_list(list) ->
        list
    end
  end

  defp table_options(%State{} = state) do
    defaults = [
      attributes: [:key | @fields],
      index: [:path, :ref],
      type: :bag
    ]

    if Mnesia.persist_to_disc?() do
      defaults
      |> Keyword.put(:disc_copies, [state.mnesia_node])
      |> Keyword.put(:ram_copies, [Node.self()])
    else
      defaults
      |> Keyword.put(:disc_copies, [])
      |> Keyword.put(:ram_copies, [state.mnesia_node, Node.self()])
    end
  end

  defp mnesia_dir(%Project{} = project) do
    project
    |> Project.workspace_path(Path.join(["indexes", "mnesia"]))
    |> ensure_directory_exists()
  end

  defp ensure_directory_exists(path) do
    File.mkdir_p!(path)
    path
  end
end
