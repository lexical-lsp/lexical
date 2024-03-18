defmodule Lexical.RemoteControl.Search.Indexer.Source do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer

  require Logger

  def index(path, source, extractors \\ nil) do
    path
    |> Document.new(source, 1)
    |> index_document(extractors)
  end

  def index_document(%Document{} = document, extractors \\ nil) do
    document
    |> Ast.analyze()
    |> Indexer.Quoted.index(extractors)
  end
end
