defimpl Lexical.Convertible, for: Lexical.SourceFile.Position do
  alias Lexical.Protocol.Conversions
  alias Lexical.SourceFile

  def to_lsp(%SourceFile.Position{} = position, context_document) do
    Conversions.to_lsp(position, context_document)
  end

  def to_native(%SourceFile.Position{} = position, _context_document) do
    {:ok, position}
  end
end
