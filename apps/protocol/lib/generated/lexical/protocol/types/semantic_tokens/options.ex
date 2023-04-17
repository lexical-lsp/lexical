# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.SemanticTokens.Options do
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

  use Proto

  deftype full: optional(one_of([boolean(), Parent.Full])),
          legend: Types.SemanticTokens.Legend,
          range: optional(one_of([boolean(), Parent.Range])),
          work_done_progress: optional(boolean())
end
