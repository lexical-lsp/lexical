# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Hover.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype content_format: optional(list_of(Types.Markup.Kind)),
          dynamic_registration: optional(boolean())
end
