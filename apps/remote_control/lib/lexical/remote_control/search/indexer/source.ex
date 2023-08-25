defmodule Lexical.RemoteControl.Search.Indexer.Source do
  alias Future.Code
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  require Logger

  @to_quoted_opts [columns: true, token_metadata: true]

  def index(path, source) do
    document = Document.new(path, source, 1)

    case Code.string_to_quoted(source, @to_quoted_opts) do
      {:ok, quoted} ->
        entries = index_quoted(document, quoted)
        {:ok, entries}

      _ ->
        Logger.error("Could not compile #{path} into AST for indexing")
        :error
    end
  end

  def index_quoted(%Document{} = document, quoted) do
    {_, reducer} =
      Macro.prewalk(quoted, Reducer.new(document), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    Reducer.entries(reducer)
  end
end
