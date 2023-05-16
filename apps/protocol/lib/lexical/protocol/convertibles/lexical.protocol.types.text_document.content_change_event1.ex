alias Lexical.Convertible
alias Lexical.Document.Edit
alias Lexical.Protocol.Types.TextDocument.ContentChangeEvent

defimpl Convertible, for: ContentChangeEvent.TextDocumentContentChangeEvent1 do
  def to_lsp(event, _context_document) do
    {:ok, event}
  end

  def to_native(%ContentChangeEvent.TextDocumentContentChangeEvent1{} = event, _context_document) do
    {:ok, Edit.new(event.text)}
  end
end
