defimpl Lexical.DocumentContainer, for: Lexical.SourceFile.DocumentEdits do
  alias Lexical.SourceFile

  def context_document(%SourceFile.DocumentEdits{} = edits, prior_context_document) do
    edits.document || prior_context_document
  end
end
