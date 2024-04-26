defmodule Lexical.RemoteControl.Dispatch.Handlers.Indexing do
  alias Lexical.Document
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Commands
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.Search

  require Logger
  import Messages

  use Dispatch.Handler, [filesystem_event(), file_changed(), file_opened()]

  def on_event(file_changed(uri: uri, open?: true), state) do
    reindex(uri)
    {:ok, state}
  end

  def on_event(file_changed(), state) do
    {:ok, state}
  end

  def on_event(file_opened(uri: uri), state) do
    # When renaming occurs, new files are only *opened* and *closed*,
    # so we need to index the new files.
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
    Commands.Reindex.uri(uri)
  end

  def delete_path(uri) do
    uri
    |> Document.Path.ensure_path()
    |> Search.Store.clear()
  end
end
