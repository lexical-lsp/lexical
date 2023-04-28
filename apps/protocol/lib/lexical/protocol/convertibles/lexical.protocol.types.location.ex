defimpl Lexical.Convertible, for: Lexical.Protocol.Types.Location do
  alias Lexical.Document
  alias Lexical.Document.Container
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types

  def to_lsp(%Types.Location{} = location, context_document) do
    with {:ok, range} <- Conversions.to_lsp(location.range, context_document) do
      {:ok, %Types.Location{location | range: range}}
    end
  end

  def to_native(%Types.Location{} = location, context_document) do
    context_document = Container.context_document(location, context_document)

    with {:ok, range} <- Conversions.to_elixir(location.range, context_document) do
      {:ok, Document.Location.new(range, context_document.uri)}
    end
  end
end
