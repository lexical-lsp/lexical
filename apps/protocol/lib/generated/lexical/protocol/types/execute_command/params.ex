# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ExecuteCommand.Params do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype arguments: optional(list_of(any())),
          command: string(),
          work_done_token: optional(Types.Progress.Token)
end
