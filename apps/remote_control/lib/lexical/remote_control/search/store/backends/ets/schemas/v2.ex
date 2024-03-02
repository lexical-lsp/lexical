defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V2 do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema

  require Entry
  use Schema, version: 2

  defkey :by_id, [:id, :type, :subtype]

  defkey :by_subject, [
    :subject,
    :type,
    :subtype,
    :path
  ]

  defkey :by_path, [:path]
  defkey :by_block_id, [:block_id, :path]
  defkey :structure, [:path]

  def migrate(_) do
    {:ok, []}
  end

  def to_rows(%Entry{} = entry) when Entry.is_structure(entry) do
    structure_key = structure(path: entry.path)
    [{structure_key, entry.subject}]
  end

  def to_rows(%Entry{} = entry) do
    subject_key =
      by_subject(
        subject: to_subject(entry.subject),
        type: entry.type,
        subtype: entry.subtype,
        path: entry.path
      )

    id_key =
      by_id(
        id: entry.id,
        type: entry.type,
        subtype: entry.subtype
      )

    path_key = by_path(path: entry.path)
    block_key = by_block_id(path: entry.path, block_id: entry.block_id)

    [{id_key, entry}, {subject_key, id_key}, {path_key, id_key}, {block_key, id_key}]
  end

  # This case will handle any namespaced entries
  def to_rows(%{type: _, subtype: _, id: _} = entry) do
    map = Map.delete(entry, :__struct__)

    Entry
    |> struct(map)
    |> to_rows()
  end

  def table_options do
    [:named_table, :ordered_set, :compressed]
  end

  def to_subject(charlist) when is_list(charlist), do: charlist
  def to_subject(:_), do: :_
  def to_subject(atom) when is_atom(atom), do: atom |> inspect() |> to_charlist()
  def to_subject(other), do: to_charlist(other)
end
