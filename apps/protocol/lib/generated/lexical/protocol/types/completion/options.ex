# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Completion.Options do
  alias Lexical.Proto
  alias __MODULE__, as: Parent

  defmodule CompletionItem do
    use Proto
    deftype label_details_support: optional(boolean())
  end

  use Proto

  deftype all_commit_characters: optional(list_of(string())),
          completion_item: optional(Parent.CompletionItem),
          resolve_provider: optional(boolean()),
          trigger_characters: optional(list_of(string())),
          work_done_progress: optional(boolean())
end
