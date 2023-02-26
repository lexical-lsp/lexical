defprotocol Lexical.Ranged.Native do
  @moduledoc """
  A protocol for converting from an LSP structure that describes
  a range to a native implementation
  """

  alias Lexical.SourceFile
  alias Lexical.SourceFile.Range

  @spec from_lsp(term, SourceFile.t()) :: {:ok, Range.t()} | {:error, term}
  def from_lsp(value, source_file)
end
