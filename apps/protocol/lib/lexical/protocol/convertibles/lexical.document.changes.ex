defimpl Lexical.Convertible, for: Lexical.Document.Changes do
  alias Lexical.Document

  def to_lsp(%Document.Changes{} = document_edits, context_document) do
    context_document = Document.Container.context_document(document_edits, context_document)
    Lexical.Convertible.to_lsp(document_edits.edits, context_document)
  end

  def to_native(%Document.Changes{} = document_edits, _) do
    {:ok, document_edits}
  end
end
