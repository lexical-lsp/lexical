defimpl Lexical.Convertible, for: Lexical.SourceFile.Range do
  alias Lexical.Protocol.Conversions
  alias Lexical.SourceFile

  def to_lsp(%SourceFile.Range{} = position, context_document) do
    Conversions.to_lsp(position, context_document)
  end

  def to_native(%SourceFile.Range{} = position, _context_document) do
    {:ok, position}
  end
end
