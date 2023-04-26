defimpl Lexical.DocumentContainer, for: Lexical.Protocol.Types.Location do
  alias Lexical.Protocol.Types
  alias Lexical.SourceFile

  def context_document(%Types.Location{} = location, parent_document) do
    case SourceFile.Store.fetch(location.uri) do
      {:ok, doc} -> doc
      _ -> parent_document
    end
  end
end
