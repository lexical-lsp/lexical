alias Lexical.Protocol.Conversions
alias Lexical.SourceFile

defimpl Lexical.Ranged.Lsp, for: Lexical.SourceFile.Position do
  alias Lexical.SourceFile.Position

  def from_native(%Position{} = position, %SourceFile{} = source_file) do
    Conversions.to_lsp(position, source_file)
  end
end

defimpl Lexical.Ranged.Lsp, for: Lexical.SourceFile.Range do
  alias Lexical.SourceFile.Range

  def from_native(%Range{} = range, %SourceFile{} = source_file) do
    Conversions.to_lsp(range, source_file)
  end
end

defimpl Lexical.Ranged.Native, for: Lexical.Protocol.Types.Position do
  alias Lexical.Protocol.Types.Position

  def from_lsp(%Position{} = position, %SourceFile{} = source_file) do
    Conversions.to_elixir(position, source_file)
  end
end

defimpl Lexical.Ranged.Native, for: Lexical.Protocol.Types.Range do
  alias Lexical.Protocol.Types.Range

  def from_lsp(%Range{} = range, %SourceFile{} = source_file) do
    Conversions.to_elixir(range, source_file)
  end
end
