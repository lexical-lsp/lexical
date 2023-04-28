defimpl Lexical.Document.Container, for: Lexical.Document.Changes do
  alias Lexical.Document

  def context_document(%Document.Changes{} = edits, prior_context_document) do
    edits.document || prior_context_document
  end
end
