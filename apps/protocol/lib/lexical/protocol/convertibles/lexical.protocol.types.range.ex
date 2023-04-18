defimpl Lexical.Convertible, for: Lexical.Protocol.Types.Range do
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types

  def to_lsp(%Types.Range{} = range, context_document) do
    Conversions.to_lsp(range, context_document)
  end

  def to_native(
        %Types.Range{
          start: %Types.Position{line: start_line, character: start_character},
          end: %Types.Position{line: end_line, character: end_character}
        } = range,
        _context_document
      )
      when start_line < 0 or start_character < 0 or end_line < 0 or end_character < 0 do
    {:error, {:invalid_range, range}}
  end

  def to_native(%Types.Range{} = range, context_document) do
    Conversions.to_elixir(range, context_document)
  end
end
