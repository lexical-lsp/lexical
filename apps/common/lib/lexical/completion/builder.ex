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

  @type result :: translated_item | :skip

  @type line_range :: {start_character :: pos_integer, end_character :: pos_integer}

  @callback snippet(Environment.t(), String.t()) :: translated_item()
  @callback snippet(Environment.t(), String.t(), item_opts) :: translated_item()

  @callback plain_text(Environment.t(), String.t()) :: translated_item()
  @callback plain_text(Environment.t(), String.t(), item_opts) :: translated_item()

  @callback text_edit(Environment.t(), String.t(), line_range) :: translated_item()
  @callback text_edit(Environment.t(), String.t(), line_range, item_opts) :: translated_item()

  @callback text_edit_snippet(Environment.t(), String.t(), line_range) :: translated_item()
  @callback text_edit_snippet(Environment.t(), String.t(), line_range, item_opts) ::
              translated_item()

  @callback fallback(any, any) :: any

  @doc """
  Boosts a translated item.

  Provides the ability to boost the relevance of an item above its peers.
  The boost is hierarchical, a single-digit boost will elevate items above other items of the same kind.
  use single-digit boosts to increase (or decrease) the prominence of individual functions or modules.
  Use the second digit to boost a certain kind of item above other kinds. For example, modules are sorted
  above functions, so they carry a default boost of 20, which will put them above functions.
  """
  @callback boost(translated_item, 0..9, 0..9) :: translated_item
  @callback boost(translated_item, 0..9) :: translated_item
  @callback boost(translated_item) :: translated_item
end
