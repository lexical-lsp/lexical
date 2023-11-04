defmodule Lexical.RemoteControl.Dispatch.Handlers.Indexing do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Indexer

  require Logger
  import Messages

  use Dispatch.Handler, [file_compile_requested(), filesystem_event()]

  def on_event(file_compile_requested(uri: uri), state) do
    reindex(uri)
    {:ok, state}
  end

  def on_event(filesystem_event(uri: uri, event_type: :deleted), state) do
    delete_path(uri)
    {:ok, state}
  end

  def on_event(filesystem_event(), state) do
    {:ok, state}
  end

  defp reindex(uri) do
    with {:ok, %Document{} = document, %Analysis{} = analysis} <-
           Document.Store.fetch(uri, :analysis),
         {:ok, entries} <- Indexer.Quoted.index(document, analysis) do
      Search.Store.update(document.path, entries)
    end
  end

  def delete_path(uri) do
    uri
    |> Document.Path.ensure_path()
    |> Search.Store.clear()
  end
end
