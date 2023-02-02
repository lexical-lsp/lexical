# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ChangeAnnotation do
  alias Lexical.Protocol.Proto
  use Proto

  deftype description: optional(string()),
          label: string(),
          needs_confirmation: optional(boolean())
end
