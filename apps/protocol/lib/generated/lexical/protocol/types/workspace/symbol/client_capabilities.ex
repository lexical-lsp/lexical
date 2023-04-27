# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Workspace.Symbol.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule ResolveSupport do
    use Proto
    deftype properties: list_of(string())
  end

  defmodule SymbolKind do
    use Proto
    deftype value_set: optional(list_of(Types.Symbol.Kind))
  end

  defmodule TagSupport do
    use Proto
    deftype value_set: list_of(Types.Symbol.Tag)
  end

  use Proto

  deftype dynamic_registration: optional(boolean()),
          resolve_support:
            optional(Lexical.Protocol.Types.Workspace.Symbol.ClientCapabilities.ResolveSupport),
          symbol_kind:
            optional(Lexical.Protocol.Types.Workspace.Symbol.ClientCapabilities.SymbolKind),
          tag_support:
            optional(Lexical.Protocol.Types.Workspace.Symbol.ClientCapabilities.TagSupport)
end
