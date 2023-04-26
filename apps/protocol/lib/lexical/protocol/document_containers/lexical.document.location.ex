defimpl Lexical.Document.Container, for: Lexical.Document.Location do
  alias Lexical.Document
  alias Lexical.Document.Location

  def context_document(%Location{source_file: %Document{} = context_document}, _) do
    context_document
  end

  def context_document(%Location{uri: uri}, context_document) when is_binary(uri) do
    case Document.Store.fetch(uri) do
      {:ok, %Document{} = source_file} ->
        source_file

      _ ->
        context_document
    end
  end
end
