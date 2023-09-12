defimpl Lexical.Convertible, for: Lexical.Document.Position do
  alias Lexical.Document
  alias Lexical.Protocol.Conversions

  def to_lsp(%Document.Position{} = position) do
    Conversions.to_lsp(position)
  end

  def to_native(%Document.Position{} = position, _context_document) do
    {:ok, position}
  end
end
