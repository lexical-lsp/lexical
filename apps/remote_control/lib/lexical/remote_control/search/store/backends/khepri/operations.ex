defmodule Lexical.RemoteControl.Search.Store.Backends.Khepri.Operations do
  @doc """
  Operations for working with the Khepri store

  This module has a normal API, but due to the fact that khepri has to rewrite any functions
  used in transactions, and it knows nothing about protocols, all the functions in this module
  shy away from using any of elixir's modules that come anywhere near protocols. That means
  No inspect, no Enum, etc. Luckily tests will fail if we include anything we shouldn't.
  """
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store.Backends.Khepri.Condition

  import Condition

  def tx_insert_many(entries) do
    :lists.foreach(&:khepri_tx.put(to_path(&1), &1), entries)
  end

  def tx_replace_all(replace_query, entries) do
    :khepri_tx.delete_many(replace_query)
    tx_insert_many(entries)
  end

  def wildcard_path do
    to_path("*", "*", "*", "*", "*")
  end

  def to_path(%Entry{} = entry) do
    safe_path = sanitize_file_system_path(entry.path)
    encoded_subject = encode_subject(entry.subject)

    [
      "entries",
      entry.type,
      entry.subtype,
      encoded_subject,
      safe_path,
      int_to_string(entry.id)
    ]
  end

  def to_path(type, subtype, subject, path, id) do
    subject = path_for(subject, &encode_subject/1)
    path = path_for(path, &sanitize_file_system_path/1)
    id = path_for(id, &int_to_string/1)

    ["entries", path_for(type), path_for(subtype), subject, path, id]
  end

  def path_for(query, formatter \\ &identity/1)
  def path_for(if_name_matches() = name, _formatter), do: name
  def path_for(if_path_matches() = path, _), do: path
  def path_for(:_, _formatter), do: wildcard()
  def path_for("*", _formatter), do: wildcard()

  def path_for(other, formatter) do
    formatter.(other)
  end

  def wildcard, do: if_name_matches()

  def encode_subject(subject) when is_binary(subject), do: subject

  def encode_subject(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> rest -> rest
      other -> ":" <> other
    end
  end

  def encode_subject(subject) when is_integer(subject) do
    int_to_string(subject)
  end

  def encode_subject(subject) when is_tuple(subject) do
    tuple_items = Tuple.to_list(subject)
    tuple_string = :lists.map(&encode_subject/1, tuple_items)
    joined = :lists.join(",", tuple_string)

    IO.iodata_to_binary(["{", joined, "}"])
  end

  defp sanitize_file_system_path(fs_path) do
    :erlang.term_to_binary(fs_path)
  end

  defp identity(i), do: i

  defp int_to_string(s) when is_binary(s), do: s
  defp int_to_string(i) when is_integer(i), do: Integer.to_string(i)
end
