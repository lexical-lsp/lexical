# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Diagnostic.Options do
  alias Lexical.Protocol.Proto
  use Proto

  deftype identifier: optional(string()),
          inter_file_dependencies: boolean(),
          work_done_progress: optional(boolean()),
          workspace_diagnostics: boolean()
end
