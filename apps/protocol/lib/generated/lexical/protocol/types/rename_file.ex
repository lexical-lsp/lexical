# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.RenameFile do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype annotation_id: optional(Types.ChangeAnnotation.Identifier),
          kind: literal("rename"),
          new_uri: string(),
          old_uri: string(),
          options: optional(Types.RenameFile.Options)
end
