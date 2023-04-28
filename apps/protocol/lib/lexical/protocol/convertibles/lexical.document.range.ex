defimpl Lexical.Convertible, for: Lexical.Document.Range do
  alias Lexical.Document
  alias Lexical.Protocol.Conversions

  def to_lsp(%Document.Range{} = position, context_document) do
    Conversions.to_lsp(position, context_document)
  end

  def to_native(%Document.Range{} = position, _context_document) do
    {:ok, position}
  end
end
