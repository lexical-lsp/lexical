defimpl Lexical.Convertible, for: Lexical.Document.Changes do
  alias Lexical.Document

  def to_lsp(%Document.Changes{} = document_edits) do
    Lexical.Convertible.to_lsp(document_edits.edits)
  end

  def to_native(%Document.Changes{} = document_edits, _) do
    {:ok, document_edits}
  end
end
