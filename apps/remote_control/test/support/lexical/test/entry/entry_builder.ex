defmodule Lexical.Test.Entry.Builder do
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.VM.Versions

  def entry(fields \\ []) do
    versions = Versions.current()

    defaults = [
      ref: make_ref(),
      path: "/foo/bar/baz.ex",
      start: {1, 1},
      finish: {1, 5},
      elixir_version: versions.elixir,
      erlang_version: versions.erlang,
      type: :module
    ]

    fields = Keyword.merge(defaults, fields)
    struct!(Entry, fields)
  end

  def definition(fields \\ []) do
    fields
    |> Keyword.put(:subtype, :definition)
    |> entry()
  end

  def reference(fields \\ []) do
    fields
    |> Keyword.put(:subtype, :reference)
    |> entry()
  end
end
