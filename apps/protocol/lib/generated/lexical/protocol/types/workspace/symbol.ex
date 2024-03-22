# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Workspace.Symbol do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule Location do
    use Proto
    deftype uri: string()
  end

  use Proto

  deftype container_name: optional(string()),
          data: optional(any()),
          kind: Types.Symbol.Kind,
          location: one_of([Types.Location, Lexical.Protocol.Types.Workspace.Symbol.Location]),
          name: string(),
          tags: optional(list_of(Types.Symbol.Tag))
end
