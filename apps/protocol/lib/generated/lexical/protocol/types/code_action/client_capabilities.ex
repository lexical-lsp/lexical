# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule CodeActionKind do
    use Proto
    deftype value_set: list_of(Types.CodeAction.Kind)
  end

  defmodule CodeActionLiteralSupport do
    use Proto
    deftype code_action_kind: Lexical.Protocol.Types.CodeAction.ClientCapabilities.CodeActionKind
  end

  defmodule ResolveSupport do
    use Proto
    deftype properties: list_of(string())
  end

  use Proto

  deftype code_action_literal_support:
            optional(
              Lexical.Protocol.Types.CodeAction.ClientCapabilities.CodeActionLiteralSupport
            ),
          data_support: optional(boolean()),
          disabled_support: optional(boolean()),
          dynamic_registration: optional(boolean()),
          honors_change_annotations: optional(boolean()),
          is_preferred_support: optional(boolean()),
          resolve_support:
            optional(Lexical.Protocol.Types.CodeAction.ClientCapabilities.ResolveSupport)
end
