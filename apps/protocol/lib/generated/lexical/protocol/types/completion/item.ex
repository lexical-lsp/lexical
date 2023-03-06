# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Completion.Item do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto

  deftype additional_text_edits: optional(list_of(Types.TextEdit)),
          command: optional(Types.Command),
          commit_characters: optional(list_of(string())),
          data: optional(any()),
          deprecated: optional(boolean()),
          detail: optional(string()),
          documentation: optional(one_of([string(), Types.Markup.Content])),
          filter_text: optional(string()),
          insert_text: optional(string()),
          insert_text_format: optional(Types.InsertTextFormat),
          insert_text_mode: optional(Types.InsertTextMode),
          kind: optional(Types.Completion.Item.Kind),
          label: string(),
          label_details: optional(Types.Completion.Item.LabelDetails),
          preselect: optional(boolean()),
          sort_text: optional(string()),
          tags: optional(list_of(Types.Completion.Item.Tag)),
          text_edit: optional(one_of([Types.TextEdit, Types.InsertReplaceEdit])),
          text_edit_text: optional(string())
end
