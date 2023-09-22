defmodule Lexical.Server.Configuration.Support do
  @moduledoc false

  alias Lexical.Protocol.Types.ClientCapabilities

  # To track a new client capability, add a new field and the path to the
  # capability in the `Lexical.Protocol.Types.ClientCapabilities` struct
  # to this mapping:
  @client_capability_mapping [
    code_action_dynamic_registration: [
      :text_document,
      :code_action,
      :dynamic_registration
    ],
    hierarchical_symbols: [
      :text_document,
      :document_symbol,
      :hierarchical_document_symbol_support
    ],
    snippet: [
      :text_document,
      :completion,
      :completion_item,
      :snippet_support
    ],
    deprecated: [
      :text_document,
      :completion,
      :completion_item,
      :deprecated_support
    ],
    tags: [
      :text_document,
      :completion,
      :completion_item,
      :tag_support
    ],
    signature_help: [
      :text_document,
      :signature_help
    ],
    work_done_progress: [
      :window,
      :work_done_progress
    ]
  ]

  defstruct code_action_dynamic_registration: false,
            hierarchical_symbols: false,
            snippet: false,
            deprecated: false,
            tags: false,
            signature_help: false,
            work_done_progress: false

  @type t :: %__MODULE__{}

  def new(%ClientCapabilities{} = client_capabilities) do
    defaults =
      for {key, path} <- @client_capability_mapping do
        value = get_in(client_capabilities, path) || false
        {key, value}
      end

    struct(__MODULE__, defaults)
  end

  def new do
    %__MODULE__{}
  end
end
