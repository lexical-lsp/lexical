defmodule Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V2 do
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schema
  alias Lexical.RemoteControl.Search.Store.Backends.Ets.Schemas.V1

  import V1, only: [query_by_subject: 1]

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

    {:ok, migrated}
  end

  def subject_to_charlist(atom) when is_atom(atom), do: atom |> inspect() |> to_charlist()
  def subject_to_charlist(other), do: to_charlist(other)
end
