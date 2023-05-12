# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.WorkDone.Progress.Begin do
  alias Lexical.Proto
  use Proto

  deftype cancellable: optional(boolean()),
          kind: literal("begin"),
          message: optional(string()),
          percentage: optional(integer()),
          title: string()
end
