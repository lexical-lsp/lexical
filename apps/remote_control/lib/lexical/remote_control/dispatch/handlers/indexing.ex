defmodule Lexical.RemoteControl.Dispatch.Handlers.Indexing do
  alias Lexical.Document
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Indexer

  require Logger
  import Messages

  use Dispatch.Handler, [file_quoted(), filesystem_event()]

  def on_event(file_quoted(document: document, quoted_ast: quoted_ast), state) do
    reindex(document, quoted_ast)
    {:ok, state}
  end

  def on_event(filesystem_event(uri: uri, event_type: :deleted), state) do
    delete_path(uri)
    {:ok, state}
  end

  def on_event(filesystem_event(), state) do
    {:ok, state}
  end

  defp reindex(%Document{} = document, quoted_ast) do
    with :ok <- ensure_latest_version(document),
         {:ok, entries} <- Indexer.Quoted.index(document, quoted_ast) do
      Search.Store.update(document.path, entries)
    end
  end

  def delete_path(uri) do
    uri
    |> Document.Path.ensure_path()
    |> Search.Store.clear()
  end

  defp ensure_latest_version(%Document{version: version, uri: uri}) do
    case Document.Store.fetch(uri) do
      {:ok, %Document{version: ^version}} ->
        :ok

      _ ->
        {:error, :version_mismatch}
    end
  end
end
