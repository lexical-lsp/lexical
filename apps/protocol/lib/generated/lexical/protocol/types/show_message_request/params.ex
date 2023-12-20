# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ShowMessageRequest.Params do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype actions: optional(list_of(Types.Message.ActionItem)),
          message: string(),
          type: Types.Message.Type
end
