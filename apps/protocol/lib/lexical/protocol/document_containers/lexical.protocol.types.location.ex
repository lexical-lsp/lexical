defimpl Lexical.Document.Container, for: Lexical.Protocol.Types.Location do
  alias Lexical.Document
  alias Lexical.Protocol.Types

  def context_document(%Types.Location{} = location, parent_document) do
    case Document.Store.fetch(location.uri) do
      {:ok, doc} -> doc
      _ -> parent_document
    end
  end
end
