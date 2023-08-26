defmodule Lexical.RemoteControl.Search.Indexer.Source do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  require Logger

  def index(path, source) do
    document = Document.new(path, source, 1)

    case Ast.from(document) do
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
      Macro.prewalk(quoted, Reducer.new(document, quoted), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    Reducer.entries(reducer)
  end
end
