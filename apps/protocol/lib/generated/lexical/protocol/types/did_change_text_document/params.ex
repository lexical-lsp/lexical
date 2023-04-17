# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.DidChangeTextDocument.Params do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype content_changes: list_of(Types.TextDocument.ContentChangeEvent),
          text_document: Types.TextDocument.Versioned.Identifier
end
