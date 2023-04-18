defprotocol Lexical.DocumentContainer do
  alias Lexical.SourceFile
  @fallback_to_any true
  @type maybe_context_document :: SourceFile.t() | nil

  @spec context_document(t, maybe_context_document()) :: maybe_context_document()
  def context_document(t, parent_context_document)
end

defimpl Lexical.DocumentContainer, for: Any do
  alias Lexical.SourceFile

  def context_document(%{source_file: %SourceFile{} = source_file}, _) do
    source_file
  end

  def context_document(%{lsp: lsp_request}, parent_context_document) do
    context_document(lsp_request, parent_context_document)
  end

  def context_document(%{text_document: %{uri: uri}}, parent_context_document) do
    case SourceFile.Store.fetch(uri) do
      {:ok, source_file} -> source_file
      _ -> parent_context_document
    end
  end

  def context_document(_, parent_context_document) do
    parent_context_document
  end
end
