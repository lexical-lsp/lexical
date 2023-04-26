defimpl Lexical.DocumentContainer, for: Lexical.SourceFile.Location do
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Location

  def context_document(%Location{source_file: %SourceFile{} = context_document}, _) do
    context_document
  end

  def context_document(%Location{uri: uri}, context_document) when is_binary(uri) do
    case SourceFile.Store.fetch(uri) do
      {:ok, %SourceFile{} = source_file} ->
        source_file

      _ ->
        context_document
    end
  end
end
