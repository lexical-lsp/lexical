# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.LinkedEditingRange.Registration.Options do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype document_selector: one_of([Types.Document.Selector, nil]),
          id: optional(string()),
          work_done_progress: optional(boolean())
end
