# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.FileOperation.Options do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype did_create: optional(Types.FileOperation.Registration.Options),
          did_delete: optional(Types.FileOperation.Registration.Options),
          did_rename: optional(Types.FileOperation.Registration.Options),
          will_create: optional(Types.FileOperation.Registration.Options),
          will_delete: optional(Types.FileOperation.Registration.Options),
          will_rename: optional(Types.FileOperation.Registration.Options)
end
