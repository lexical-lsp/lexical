defimpl Lexical.Convertible, for: Lexical.SourceFile.Edit do
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types
  alias Lexical.SourceFile

  def to_lsp(%SourceFile.Edit{range: nil} = edit, _context_document) do
    {:ok, Types.TextEdit.new(new_text: edit.text, range: nil)}
  end

  def to_lsp(%SourceFile.Edit{} = edit, context_document) do
    with {:ok, range} <- Conversions.to_lsp(edit.range, context_document) do
      {:ok, Types.TextEdit.new(new_text: edit.text, range: range)}
    end
  end

  def to_native(%SourceFile.Edit{} = edit, _context_document) do
    {:ok, edit}
  end
end
