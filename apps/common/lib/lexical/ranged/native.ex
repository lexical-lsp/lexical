defprotocol Lexical.Ranged.Native do
  alias Lexical.SourceFile

  @spec from_lsp(term, SourceFile.t()) :: {:ok, term} | {:error, term}
  def from_lsp(value, source_file)
end
