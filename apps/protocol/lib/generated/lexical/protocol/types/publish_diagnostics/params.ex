# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.PublishDiagnostics.Params do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto
  deftype diagnostics: list_of(Types.Diagnostic), uri: string(), version: optional(integer())
end
