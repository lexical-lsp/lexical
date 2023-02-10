defprotocol Lexical.Ranged.Lsp do
  alias Lexical.SourceFile

  @spec from_native(term, SourceFile.t()) :: term
  def from_native(value, source_file)
end
