# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.SemanticTokens.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule Full do
    use Proto
    deftype delta: optional(boolean())
  end

  defmodule Range do
    use Proto
    deftype []
  end

  defmodule Requests do
    use Proto

    deftype full: optional(one_of([boolean(), Parent.Full])),
            range: optional(one_of([boolean(), Parent.Range]))
  end

  use Proto

  deftype augments_syntax_tokens: optional(boolean()),
          dynamic_registration: optional(boolean()),
          formats: list_of(Types.TokenFormat),
          multiline_token_support: optional(boolean()),
          overlapping_token_support: optional(boolean()),
          requests: Parent.Requests,
          server_cancel_support: optional(boolean()),
          token_modifiers: list_of(string()),
          token_types: list_of(string())
end
