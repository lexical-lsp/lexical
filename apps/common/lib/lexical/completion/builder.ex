defmodule Lexical.Completion.Builder do
  @type insert_text_format :: :plain_text | :snippet

  @type completion_item_kind ::
          :text
          | :method
          | :function
          | :constructor
          | :field
          | :variable
          | :class
          | :interface
          | :module
          | :property
          | :unit
          | :value
          | :enum
          | :keyword
          | :snippet
          | :color
          | :file
          | :reference
          | :folder
          | :enum_member
          | :constant
          | :struct
          | :event
          | :operator
          | :type_parameter

  @type completion_item_tag :: :deprecated

  @type item_opt ::
          {:deprecated, boolean}
          | {:detail, String.t()}
          | {:documentation, String.t()}
          | {:filter_text, String.t()}
          | {:insert_text, String.t()}
          | {:kind, completion_item_kind}
          | {:label, String.t()}
          | {:preselect, boolean()}
          | {:sort_text, String.t()}
          | {:tags, [completion_item_tag]}

  @type item_opts :: [item_opt]

  @type maybe_string :: String.t() | nil

  @opaque translated_item :: %{
            detail: maybe_string(),
            documentation: maybe_string(),
            filter_text: maybe_string(),
            insert_text: String.t(),
            kind: completion_item_kind(),
            label: String.t(),
            preselect: boolean | nil,
            sort_text: maybe_string(),
            tags: [completion_item_tag] | nil
          }

  @type result :: translated_item() | :skip

  @type t :: module()

  @callback snippet(String.t()) :: result
  @callback snippet(String.t(), item_opt) :: result

  @callback plain_text(String.t()) :: result
  @callback plain_text(String.t(), item_opt) :: result

  @callback fallback(any, any) :: any
  @callback boost(translated_item, 0..10) :: translated_item
end
