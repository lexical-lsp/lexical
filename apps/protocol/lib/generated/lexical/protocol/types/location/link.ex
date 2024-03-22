# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Location.Link do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype origin_selection_range: optional(Types.Range),
          target_range: Types.Range,
          target_selection_range: Types.Range,
          target_uri: string()
end
