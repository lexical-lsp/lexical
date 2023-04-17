# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.DeleteFile do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype annotation_id: optional(Types.ChangeAnnotation.Identifier),
          kind: literal("delete"),
          options: optional(Types.DeleteFile.Options),
          uri: string()
end
