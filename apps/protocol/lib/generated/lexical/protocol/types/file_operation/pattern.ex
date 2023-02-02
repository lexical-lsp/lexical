# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.FileOperation.Pattern do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype glob: string(),
          matches: optional(Types.FileOperation.Pattern.Kind),
          options: optional(Types.FileOperation.Pattern.Options)
end
