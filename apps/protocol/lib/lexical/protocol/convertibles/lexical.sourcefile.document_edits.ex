defimpl Lexical.Convertible, for: Lexical.SourceFile.DocumentEdits do
  alias Lexical.DocumentContainer
  alias Lexical.SourceFile

  def to_lsp(%SourceFile.DocumentEdits{} = document_edits, context_document) do
    context_document = DocumentContainer.context_document(document_edits, context_document)
    Lexical.Convertible.to_lsp(document_edits.edits, context_document)
  end

  def to_native(%SourceFile.DocumentEdits{} = document_edits, _) do
    {:ok, document_edits}
  end
end
