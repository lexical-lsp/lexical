defimpl Lexical.Convertible, for: Lexical.SourceFile.Location do
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Conversions
  alias Lexical.SourceFile

  def to_lsp(%SourceFile.Location{} = location, %SourceFile{} = context_document) do
    with {:ok, range} <- Conversions.to_lsp(location.range, context_document) do
      uri = SourceFile.Location.uri(location)
      {:ok, Types.Location.new(uri: uri, range: range)}
    end
  end

  def to_native(%SourceFile.Location{} = location, _context_document) do
    {:ok, location}
  end
end
