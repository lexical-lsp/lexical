# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction.Context do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype diagnostics: list_of(Types.Diagnostic),
          only: optional(list_of(Types.CodeAction.Kind)),
          trigger_kind: optional(Types.CodeAction.Trigger.Kind)
end
