alias Lexical.Protocol.Conversions
alias Lexical.Protocol.Types
alias Lexical.Ranged
alias Lexical.SourceFile

defimpl Ranged.Lsp, for: Types.Location do
  def from_native(%Types.Location{} = location, _) do
    with {:ok, source_file} <- SourceFile.Store.open_temporary(location.uri) do
      Conversions.to_lsp(location.range, source_file)
    end
  end
end

defimpl Ranged.Native, for: Types.Location do
  def from_lsp(%Types.Location{} = location, _) do
    with {:ok, source_file} <- SourceFile.Store.open_temporary(location.uri) do
      Conversions.to_elixir(location.range, source_file)
    end
  end
end
