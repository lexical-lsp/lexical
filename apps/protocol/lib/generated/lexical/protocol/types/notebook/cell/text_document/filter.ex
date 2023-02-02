# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Notebook.Cell.TextDocument.Filter do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype language: optional(string()),
          notebook: one_of([string(), Types.Notebook.Document.Filter])
end
