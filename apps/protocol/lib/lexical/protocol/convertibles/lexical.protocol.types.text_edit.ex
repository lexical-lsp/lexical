defimpl Lexical.Convertible, for: Lexical.Protocol.Types.TextEdit do
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types
  alias Lexical.SourceFile

  def to_lsp(%Types.TextEdit{} = text_edit, context_document) do
    with {:ok, range} <- Conversions.to_lsp(text_edit.range, context_document) do
      {:ok, %Types.TextEdit{text_edit | range: range}}
    end
  end

  def to_native(%Types.TextEdit{range: nil} = text_edit, _context_document) do
    {:ok, SourceFile.Edit.new(text_edit.new_text)}
  end

  def to_native(%Types.TextEdit{} = text_edit, context_document) do
    with {:ok, %SourceFile.Range{} = range} <-
           Conversions.to_elixir(text_edit.range, context_document) do
      {:ok, SourceFile.Edit.new(text_edit.new_text, range)}
    end
  end
end
