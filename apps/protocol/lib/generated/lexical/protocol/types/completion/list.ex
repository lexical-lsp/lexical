# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Completion.List do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types

  defmodule EditRange do
    use Proto
    deftype insert: Types.Range, replace: Types.Range
  end

  defmodule ItemDefaults do
    use Proto

    deftype commit_characters: optional(list_of(string())),
            data: optional(any()),
            edit_range: optional(one_of([Types.Range, EditRange])),
            insert_text_format: optional(Types.InsertTextFormat),
            insert_text_mode: optional(Types.InsertTextMode)
  end

  use Proto

  deftype is_incomplete: boolean(),
          item_defaults: optional(ItemDefaults),
          items: list_of(Types.Completion.Item)
end
