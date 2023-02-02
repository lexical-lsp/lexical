# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.TextDocument.OptionalVersioned.Identifier do
  alias Lexical.Protocol.Proto
  use Proto
  deftype uri: string(), version: one_of([integer(), nil])
end
