defmodule Lexical.RemoteControl.Search.Indexer.Source do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer

  require Logger

  def index(path, source) do
    document = Document.new(path, source, 1)
    analysis = Ast.analyze(document)
    Indexer.Quoted.index(document, analysis)
  end
end
