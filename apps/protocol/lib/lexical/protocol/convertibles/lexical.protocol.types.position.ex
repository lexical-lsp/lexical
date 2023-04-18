defimpl Lexical.Convertible, for: Lexical.Protocol.Types.Position do
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types

  def to_lsp(%Types.Position{} = position, context_document) do
    Conversions.to_lsp(position, context_document)
  end

  def to_native(%Types.Position{} = position, context_document) do
    Conversions.to_elixir(position, context_document)
  end
end
