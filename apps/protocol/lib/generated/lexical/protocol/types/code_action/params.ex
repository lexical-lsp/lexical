# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction.Params do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype context: Types.CodeAction.Context,
          partial_result_token: optional(Types.Progress.Token),
          range: Types.Range,
          text_document: Types.TextDocument.Identifier,
          work_done_token: optional(Types.Progress.Token)
end
