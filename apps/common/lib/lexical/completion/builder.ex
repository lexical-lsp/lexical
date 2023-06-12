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
  The boost is hierarchical, and split into a local boost and a global boost.
  Use the local boost to increase (or decrease) the prominence of individual functions or modules relative to another
  item of the same type. For example, you can use the local boost to increase the prominence of test functions inside of test files.
  Use the global boost to boost a certain kind of item above other kinds. For example, modules are sorted
  above functions, so they carry a global boost of 2, which will put them above functions, which have no global boost.
  """
  @callback boost(translated_item, local_boost :: 0..9, global_boost :: 0..9) :: translated_item
  @callback boost(translated_item, local_bost :: 0..9) :: translated_item
  @callback boost(translated_item) :: translated_item
end
