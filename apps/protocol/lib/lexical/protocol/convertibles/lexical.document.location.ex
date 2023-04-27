defimpl Lexical.Convertible, for: Lexical.Document.Location do
  alias Lexical.Document
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types

  def to_lsp(%Document.Location{} = location, %Document{} = context_document) do
    with {:ok, range} <- Conversions.to_lsp(location.range, context_document) do
      uri = Document.Location.uri(location)
      {:ok, Types.Location.new(uri: uri, range: range)}
    end
  end

  def to_native(%Document.Location{} = location, _context_document) do
    {:ok, location}
  end
end
