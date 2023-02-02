defmodule Lexical.SourceFile.Conversions do
  @moduledoc """
  Functions to convert between language server representations and elixir-native representations.

  The LSP protocol defines positions in terms of their utf-16 representation (thanks, windows),
  so when a document change comes in, we need to recalculate the positions of the change if
  the line contains non-ascii characters. If it's a pure ascii line, then the positions
  are the same in both utf-8 and utf-16, since they reference characters and not bytes.
  """

  def ensure_uri("file://" <> _ = uri), do: uri

  def ensure_uri(path),
    do: Lexical.SourceFile.Path.to_uri(path)

  def ensure_path("file://" <> _ = uri),
    do: Lexical.SourceFile.Path.from_uri(uri)

  def ensure_path(path), do: path
end
