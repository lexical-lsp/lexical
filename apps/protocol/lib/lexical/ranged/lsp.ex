defprotocol Lexical.Ranged.Lsp do
  @moduledoc """
  A protocol describing converting to a LSP range
  """
  alias Lexical.SourceFile
  alias Lexical.Protocol.Types.Range

  @spec from_native(term, SourceFile.t()) :: Range.t()
  def from_native(value, source_file)
end
