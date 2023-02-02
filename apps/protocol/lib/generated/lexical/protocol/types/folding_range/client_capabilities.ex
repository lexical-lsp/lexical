# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.FoldingRange.ClientCapabilities do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule FoldingRange do
    use Proto
    deftype collapsed_text: optional(boolean())
  end

  defmodule FoldingRangeKind do
    use Proto
    deftype value_set: optional(list_of(Types.FoldingRange.Kind))
  end

  use Proto

  deftype dynamic_registration: optional(boolean()),
          folding_range: optional(Parent.FoldingRange),
          folding_range_kind: optional(Parent.FoldingRangeKind),
          line_folding_only: optional(boolean()),
          range_limit: optional(integer())
end
