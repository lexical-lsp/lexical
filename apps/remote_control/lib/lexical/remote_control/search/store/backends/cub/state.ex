defmodule Lexical.RemoteControl.Search.Store.Backends.Cub.State do
  @moduledoc """
  A cubdb schema and functions for data manipulation

  CubDB is an... interesting database. It relies on erlang term ordering, which is documented below.
  Furthermore, the positions of the records are significant in picking the ranges of things that we
  must iterate over in order to limit the amount of stuff each `select` call sees.

  ## Schema description

  The schema presented here does a couple interesting things in order to be efficient and easy-ish
  to work on. We need to do the following things:

    1. Keep a set of entities organized by their subject, type and subtype.
    2. Keep a set of entities organized by their reference (which is effectively an id)
    3. Be able to delete all entities that belong to a given path

  To that end, we store whole entities under the `subject_key` and `ref_key`, which leads to some
  duplication, but improves query performance, as there's no indirection when we do a subject
  search.

  We store both `ref_key` and `subject_key` entries under the path_key entry. This allows us to
  delete entries by path fairly efficiently, as we've enumerated every key that contains a given path,
  and since `subject_keys` contain a path, only those subjects in a path will be deleted.
  """
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.VM.Versions

  import Record

  defrecord :path_key, sort_key: 1, path: nil

  defrecord :subject_key, type: nil, subtype: nil, subject: nil

  defrecord :ref_key, id: nil

  defstruct project: nil, leader?: false, leader_pid: nil, cub_pid: nil

  # Erlang's total ordering
  # number < atom < reference < fun < port < pid < tuple < map < nil < list < bit string

  def new_leader(%Project{} = project, cub_pid) do
    %__MODULE__{
      project: project,
      leader_pid: self(),
      leader?: true,
      cub_pid: cub_pid
    }
  end

  def new_follower(%Project{} = project, leader_pid) do
    %__MODULE__{
      leader_pid: leader_pid,
      leader?: false,
      project: project
    }
  end

  def prepare(%__MODULE__{leader?: true} = state) do
    case CubDB.size(state.cub_pid) do
      0 -> {:ok, :empty}
      _n -> {:ok, :stale}
    end
  end

  def prepare(%__MODULE__{}) do
    {:ok, :stale}
  end

  def insert(%__MODULE__{} = state, entries) do
    CubDB.put_multi(state.cub_pid, entries_to_keys_and_values(entries))
  end

  def drop(%__MODULE__{} = state) do
    CubDB.clear(state.cub_pid)
  end

  def replace_all(%__MODULE__{} = state, entries) do
    keys_and_values = entries_to_keys_and_values(entries)

    CubDB.transaction(state.cub_pid, fn transaction ->
      CubDB.Tx.clear(transaction)

      transaction =
        Enum.reduce(keys_and_values, transaction, fn {key, value}, transaction ->
          CubDB.Tx.put(transaction, key, value)
        end)

      {:commit, transaction, :ok}
    end)
  end

  def delete_by_path(%__MODULE__{} = state, path) do
    CubDB.transaction(state.cub_pid, fn transaction ->
      path_key = path_key(path: path)

      {subject_keys, ref_keys} =
        transaction
        |> CubDB.Tx.get(path_key, [])
        |> Enum.unzip()

      deleted_entries = Enum.map(ref_keys, &CubDB.Tx.get(transaction, &1))

      keys_to_delete = [path_key | subject_keys ++ ref_keys]

      transaction =
        Enum.reduce(keys_to_delete, transaction, fn key, tx ->
          CubDB.Tx.delete(tx, key)
        end)

      {:commit, transaction, {:ok, deleted_entries}}
    end)
  end

  def find_by_subject(%__MODULE__{} = state, type, subtype, subject) do
    versions = Versions.current()

    CubDB.with_snapshot(state.cub_pid, fn snap ->
      snap
      |> CubDB.Snapshot.select(min_key: min_subject_key(), max_key: max_subject_key())
      |> Stream.flat_map(fn
        {subject_key(subject: db_subject), entries} ->
          Enum.filter(entries, fn entry ->
            correct_version_range?(entry, versions) and
              subject_matches?(db_subject, subject) and
              type_and_subtype_match?(entry, type, subtype)
          end)
      end)
      |> Enum.to_list()
    end)
  end

  def find_by_references(%__MODULE__{} = state, type, subtype, references) do
    versions = Versions.current()

    all_ref_keys = Enum.map(references, fn ref -> ref_key(id: ref) end)

    state.cub_pid
    |> CubDB.get_multi(all_ref_keys)
    |> Stream.filter(fn {_, entry} ->
      correct_version_range?(entry, versions) and
        type_and_subtype_match?(entry, type, subtype)
    end)
    |> Enum.map(fn {_, entry} -> entry end)
  end

  def select_all(%__MODULE__{} = state) do
    min_key = min_ref_key()
    max_key = max_ref_key()

    state.cub_pid
    |> CubDB.select(min_key: min_key, max_key: max_key)
    |> Enum.map(fn {_, value} -> value end)
  end

  defp new_subject_key(%Entry{} = entry) do
    subject_key(subject: to_subject(entry.subject), type: entry.type, subtype: entry.subtype)
  end

  defp entries_to_keys_and_values(entries) do
    by_subject = Enum.group_by(entries, &new_subject_key(&1), & &1)

    by_path =
      Enum.group_by(
        entries,
        &path_key(path: &1.path),
        &{new_subject_key(&1), ref_key(id: &1.ref)}
      )

    by_ref = Enum.map(entries, &{ref_key(id: &1.ref), &1})

    Enum.concat([by_subject, by_path, by_ref])
  end

  defp subject_matches?(db_subject, query_subject) do
    do_subject_matches?(db_subject, to_subject(query_subject))
  end

  defp do_subject_matches?(_, :_), do: true

  defp do_subject_matches?(same_subject, same_subject) when is_binary(same_subject) do
    true
  end

  defp do_subject_matches?(_, _), do: false

  defp correct_version_range?(%Entry{} = entry, versions) do
    entry.elixir_version == versions.elixir and entry.erlang_version == versions.erlang
  end

  defp type_and_subtype_match?(%Entry{type: type}, type, :_) do
    true
  end

  defp type_and_subtype_match?(%Entry{subtype: subtype}, :_, subtype) do
    true
  end

  defp type_and_subtype_match?(%Entry{type: type, subtype: subtype}, type, subtype) do
    true
  end

  defp type_and_subtype_match?(%Entry{}, _type, _subtype) do
    false
  end

  defp min_subject_key do
    subject_key(
      type: min_for_type(:atom),
      subtype: min_for_type(:atom),
      subject: min_for_type(:binary)
    )
  end

  defp max_subject_key do
    subject_key(type: max_for_type(:atom), subtype: max_for_type(:atom))
  end

  defp min_ref_key do
    ref_key(id: 0)
  end

  defp max_ref_key do
    ref_key(id: "")
  end

  defp min_for_type(:integer), do: 0
  defp min_for_type(:atom), do: 0
  defp min_for_type(:binary), do: nil

  defp max_for_type(:atom), do: ""
  defp max_for_type(:integer), do: :""

  defp to_subject(binary) when is_binary(binary), do: binary
  defp to_subject(:_), do: :_
  defp to_subject(atom) when is_atom(atom), do: inspect(atom)
  defp to_subject(other), do: to_string(other)
end
