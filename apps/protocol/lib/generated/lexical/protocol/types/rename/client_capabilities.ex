# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Rename.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype dynamic_registration: optional(boolean()),
          honors_change_annotations: optional(boolean()),
          prepare_support: optional(boolean()),
          prepare_support_default_behavior: optional(Types.PrepareSupportDefaultBehavior)
end
