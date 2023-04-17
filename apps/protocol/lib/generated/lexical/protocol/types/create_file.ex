# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CreateFile do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype annotation_id: optional(Types.ChangeAnnotation.Identifier),
          kind: literal("create"),
          options: optional(Types.CreateFile.Options),
          uri: string()
end
