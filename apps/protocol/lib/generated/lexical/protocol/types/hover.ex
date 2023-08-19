# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Hover do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype contents:
            one_of([Types.Markup.Content, Types.MarkedString, list_of(Types.MarkedString)]),
          range: optional(Types.Range)
end
