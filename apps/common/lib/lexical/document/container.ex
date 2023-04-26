defprotocol Lexical.Document.Container do
  alias Lexical.Document
  @fallback_to_any true
  @type maybe_context_document :: Document.t() | nil

  @spec context_document(t, maybe_context_document()) :: maybe_context_document()
  def context_document(t, parent_context_document)
end

defimpl Lexical.Document.Container, for: Any do
  alias Lexical.Document

  def context_document(%{source_file: %Document{} = source_file}, _) do
    source_file
  end

  def context_document(%{lsp: lsp_request}, parent_context_document) do
    context_document(lsp_request, parent_context_document)
  end

  def context_document(%{text_document: %{uri: uri}}, parent_context_document) do
    case Document.Store.fetch(uri) do
      {:ok, source_file} -> source_file
      _ -> parent_context_document
    end
  end

  def context_document(_, parent_context_document) do
    parent_context_document
  end
end
