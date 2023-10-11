defmodule Lexical.Test.Entry.Builder do
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.VM.Versions

  import Lexical.Test.PositionSupport

  def entry(fields \\ []) do
    versions = Versions.current()

    defaults = [
      subject: Module,
      ref: make_ref(),
      path: "/foo/bar/baz.ex",
      range: range(1, 1, 1, 5),
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

  defp range(start_line, start_column, end_line, end_column) do
    Range.new(position(start_line, start_column), position(end_line, end_column))
  end
end
