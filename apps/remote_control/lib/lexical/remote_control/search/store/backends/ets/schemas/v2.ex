defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V2 do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V1

  import V1, only: [query_by_subject: 1, by_id: 1, by_path: 1]

  use Schema, version: 2

  defkey :by_subject_prefix, [
    :subject,
    :type,
    :subtype,
    :elixir_version,
    :erlang_version,
    :path
  ]

  def migrate(entries) do
    migrated =
      entries
      |> migrate_v0_to_v2()
      |> migrate_v1_to_v2()

    {:ok, migrated}
  end

  defp migrate_v1_to_v2(entries) do
    entries
    |> Stream.map(fn
      {query_by_subject(
         subject: subject,
         type: type,
         subtype: subtype,
         elixir_version: elixir_version,
         erlang_version: erlang_version,
         path: path
       ), v} ->
        {query_by_subject_prefix(
           subject: subject_to_charlist(subject),
           type: type,
           subtype: subtype,
           elixir_version: elixir_version,
           erlang_version: erlang_version,
           path: path
         ), v}

      other ->
        other
    end)
    |> Enum.to_list()
  end

  defp migrate_v0_to_v2(entries) do
    entries
    |> Stream.filter(fn
      {_, %_{elixir_version: _, erlang_version: _, type: _, subtype: _, ref: _}} -> true
      _ -> false
    end)
    |> Stream.map(fn {_, entry} -> entry end)
    |> entries_to_rows()
  end

  @spec entries_to_rows(Enumerable.t(Entry.t())) :: [tuple()]
  def entries_to_rows(entries) do
    entries
    |> Stream.flat_map(&to_rows(&1))
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.update(acc, key, [value], fn old_values -> [value | old_values] end)
    end)
    |> Enum.to_list()
  end

  def to_rows(%Entry{} = entry) do
    subject_prefix_key =
      by_subject_prefix(
        elixir_version: entry.elixir_version,
        erlang_version: entry.erlang_version,
        subject: subject_to_charlist(entry.subject),
        type: entry.type,
        subtype: entry.subtype,
        path: entry.path
      )

    id_key =
      by_id(
        id: entry.ref,
        type: entry.type,
        subtype: entry.subtype,
        elixir_version: entry.elixir_version,
        erlang_version: entry.erlang_version
      )

    path_key = by_path(path: entry.path)

    [{subject_prefix_key, entry}, {id_key, entry}, {path_key, id_key}]
  end

  # This case will handle any namespaced entries
  def to_rows(%{elixir_version: _, erlang_version: _, type: _, subtype: _, ref: _} = entry) do
    map = Map.delete(entry, :__struct__)

    Entry
    |> struct(map)
    |> to_rows()
  end

  def table_options do
    [:named_table, :ordered_set]
  end

  def subject_to_charlist(charlist) when is_list(charlist), do: charlist
  def subject_to_charlist(:_), do: :_
  def subject_to_charlist(atom) when is_atom(atom), do: atom |> inspect() |> to_charlist()
  def subject_to_charlist(other), do: to_charlist(other)
end
