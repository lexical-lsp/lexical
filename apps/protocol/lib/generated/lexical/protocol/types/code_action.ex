# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule Disabled do
    use Proto
    deftype reason: string()
  end

  use Proto

  deftype command: optional(Types.Command),
          data: optional(any()),
          diagnostics: optional(list_of(Types.Diagnostic)),
          disabled: optional(Lexical.Protocol.Types.CodeAction.Disabled),
          edit: optional(Types.Workspace.Edit),
          is_preferred: optional(boolean()),
          kind: optional(Types.CodeAction.Kind),
          title: string()
end
