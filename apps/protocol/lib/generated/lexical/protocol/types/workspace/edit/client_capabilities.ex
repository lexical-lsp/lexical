# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Workspace.Edit.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule ChangeAnnotationSupport do
    use Proto
    deftype groups_on_label: optional(boolean())
  end

  use Proto

  deftype change_annotation_support:
            optional(
              Lexical.Protocol.Types.Workspace.Edit.ClientCapabilities.ChangeAnnotationSupport
            ),
          document_changes: optional(boolean()),
          failure_handling: optional(Types.FailureHandling.Kind),
          normalizes_line_endings: optional(boolean()),
          resource_operations: optional(list_of(Types.ResourceOperation.Kind))
end
