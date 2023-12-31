defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V1 do
  @moduledoc """
  This schema  uses a bit of data duplication in order to achieve good performance.

  It does this by storing data under three different key types. The first type groups references to ids by
  path, and is accessible via the `by_path` utility macros. The second, stores data by subject, type, subtype,
  path and the elixir and erlang versions. This is what powers exact matching.
  Finally, entries are stored by their reference, which powers direct lookups, which are used in fuzzy matching.

  """
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

  defkey :by_path, [:path]

  def migrate(entries) do
    {:ok, entries}
  end
end
