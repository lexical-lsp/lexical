defimpl Lexical.Convertible, for: Lexical.Document.Changes do
  alias Lexical.Document

  def to_lsp(%Document.Changes{} = changes) do
    Lexical.Convertible.to_lsp(changes.edits)
  end

  def to_native(%Document.Changes{} = changes, _) do
    {:ok, changes}
  end
end
