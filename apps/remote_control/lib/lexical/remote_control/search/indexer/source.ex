defmodule Lexical.RemoteControl.Search.Indexer.Source do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer

  require Logger

  def index(path, source) do
    document = Document.new(path, source, 1)

    case Ast.from(document) do
      {:ok, quoted} ->
        Indexer.Quoted.index(document, quoted)

      _ ->
        Logger.error("Could not compile #{path} into AST for indexing")
        :error
    end
  end
end
