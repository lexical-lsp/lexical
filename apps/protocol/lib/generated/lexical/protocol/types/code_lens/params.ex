# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeLens.Params do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype partial_result_token: optional(Types.Progress.Token),
          text_document: Types.TextDocument.Identifier,
          work_done_token: optional(Types.Progress.Token)
end
