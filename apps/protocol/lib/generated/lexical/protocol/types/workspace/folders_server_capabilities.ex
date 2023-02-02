# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Workspace.FoldersServerCapabilities do
  alias Lexical.Protocol.Proto
  use Proto

  deftype change_notifications: optional(one_of([string(), boolean()])),
          supported: optional(boolean())
end
