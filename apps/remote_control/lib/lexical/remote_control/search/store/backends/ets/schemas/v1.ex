defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V1 do
  @moduledoc """
  This schema  uses a bit of data duplication in order to achieve good performance.

  It does this by storing data under three different key types. The first type groups references to ids by
  path, and is accessible via the `by_path` utility macros. The second, stores data by subject, type, subtype,
  path and the elixir and erlang versions. This is what powers exact matching.
  Finally, entries are stored by their reference, which powers direct lookups, which are used in fuzzy matching.

  """

  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema

  use Schema, version: 1

  defkey :by_id, [:id, :type, :subtype, :elixir_version, :erlang_version]

  defkey :by_subject, [
    :subject,
    :type,
    :subtype,
    :elixir_version,
    :erlang_version,
    :path
  ]

  defkey :by_prefix, [
    :prefix,
    :type,
    :subtype,
    :elixir_version,
    :erlang_version
  ]

  defkey :by_path, [:path]

  def migrate(entries) do
    migrated =
      entries
      |> Stream.filter(fn
        {_, %_{elixir_version: _, erlang_version: _, type: _, subtype: _, ref: _}} -> true
        _ -> false
      end)
      |> Stream.map(fn {_, entry} -> entry end)
      |> entries_to_rows()

    {:ok, migrated}
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
    subject_key =
      by_subject(
        elixir_version: entry.elixir_version,
        erlang_version: entry.erlang_version,
        subject: to_subject(entry.subject),
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

    prefix_key =
      by_prefix(
        prefix: to_prefix(entry.subject),
        type: entry.type,
        subtype: entry.subtype,
        elixir_version: entry.elixir_version,
        erlang_version: entry.erlang_version
      )

    path_key = by_path(path: entry.path)

    [{subject_key, entry}, {prefix_key, entry}, {id_key, entry}, {path_key, id_key}]
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

  defp to_subject(binary) when is_binary(binary), do: binary
  defp to_subject(:_), do: :_
  defp to_subject(atom) when is_atom(atom), do: inspect(atom)
  defp to_subject(other), do: to_string(other)

  defp to_prefix(atom) when is_atom(atom), do: atom |> inspect() |> to_charlist()
  defp to_prefix(other), do: to_charlist(other)
end
