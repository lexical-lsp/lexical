defmodule Lexical.Completion.Builder do
  alias Lexical.Completion.Environment

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
            __struct__: module(),
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

  @type t :: module()

  @type result :: t | :skip

  @callback snippet(Environment.t(), String.t()) :: translated_item()
  @callback snippet(Environment.t(), String.t(), item_opts) :: translated_item()

  @callback plain_text(Environment.t(), String.t()) :: translated_item()
  @callback plain_text(Environment.t(), String.t(), item_opts) :: translated_item()

  @callback fallback(any, any) :: any
  @callback boost(String.t(), 0..10) :: String.t()
end
