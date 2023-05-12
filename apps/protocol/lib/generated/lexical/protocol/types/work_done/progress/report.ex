# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.WorkDone.Progress.Report do
  alias Lexical.Proto
  use Proto

  deftype cancellable: optional(boolean()),
          kind: literal("report"),
          message: optional(string()),
          percentage: optional(integer())
end
