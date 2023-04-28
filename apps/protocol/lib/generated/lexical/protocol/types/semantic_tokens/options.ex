# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.SemanticTokens.Options do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule Full do
    use Proto
    deftype delta: optional(boolean())
  end

  defmodule Range do
    use Proto
    deftype []
  end

  use Proto

  deftype full: optional(one_of([boolean(), Lexical.Protocol.Types.SemanticTokens.Options.Full])),
          legend: Types.SemanticTokens.Legend,
          range:
            optional(one_of([boolean(), Lexical.Protocol.Types.SemanticTokens.Options.Range])),
          work_done_progress: optional(boolean())
end
