# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.TextDocument.Edit do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype edits: list_of(one_of([Types.TextEdit, Types.TextEdit.Annotated])),
          text_document: Types.TextDocument.OptionalVersioned.Identifier
end
