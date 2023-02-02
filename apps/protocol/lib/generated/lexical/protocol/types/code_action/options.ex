# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction.Options do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype code_action_kinds: optional(list_of(Types.CodeAction.Kind)),
          resolve_provider: optional(boolean()),
          work_done_progress: optional(boolean())
end
