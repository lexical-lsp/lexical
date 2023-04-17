# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.InlayHint.ClientCapabilities do
  alias Lexical.Proto
  alias __MODULE__, as: Parent

  defmodule ResolveSupport do
    use Proto
    deftype properties: list_of(string())
  end

  use Proto

  deftype dynamic_registration: optional(boolean()),
          resolve_support: optional(Parent.ResolveSupport)
end
