# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.CodeAction do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule Disabled do
    use Proto
    deftype reason: string()
  end

  use Proto

  deftype command: optional(Types.Command),
          data: optional(any()),
          diagnostics: optional(list_of(Types.Diagnostic)),
          disabled: optional(Parent.Disabled),
          edit: optional(Types.Workspace.Edit),
          is_preferred: optional(boolean()),
          kind: optional(Types.CodeAction.Kind),
          title: string()
end
