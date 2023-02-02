# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Document.Formatting.Params do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype options: Types.Formatting.Options,
          text_document: Types.TextDocument.Identifier,
          work_done_token: optional(Types.Progress.Token)
end
