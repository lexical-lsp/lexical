defimpl Lexical.Convertible, for: Lexical.Document.Range do
  alias Lexical.Document
  alias Lexical.Protocol.Conversions

  def to_lsp(%Document.Range{} = range) do
    Conversions.to_lsp(range)
  end

  def to_native(%Document.Range{} = range, _context_document) do
    {:ok, range}
  end
end
