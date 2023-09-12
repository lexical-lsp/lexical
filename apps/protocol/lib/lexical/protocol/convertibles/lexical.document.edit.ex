defimpl Lexical.Convertible, for: Lexical.Document.Edit do
  alias Lexical.Document
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types

  def to_lsp(%Document.Edit{range: nil} = edit) do
    {:ok, Types.TextEdit.new(new_text: edit.text, range: nil)}
  end

  def to_lsp(%Document.Edit{} = edit) do
    with {:ok, range} <- Conversions.to_lsp(edit.range) do
      {:ok, Types.TextEdit.new(new_text: edit.text, range: range)}
    end
  end

  def to_native(%Document.Edit{} = edit, _context_document) do
    {:ok, edit}
  end
end
