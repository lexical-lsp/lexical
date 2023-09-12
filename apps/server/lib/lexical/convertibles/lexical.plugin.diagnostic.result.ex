defimpl Lexical.Convertible, for: Lexical.Plugin.V1.Diagnostic.Result do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Math
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types
  alias Lexical.Text

  def to_lsp(%Diagnostic.Result{} = diagnostic, _context_document) do
    with {:ok, document} <- Document.Store.open_temporary(diagnostic.uri),
         {:ok, lsp_range} <- position_to_range(document, diagnostic.position) do
      proto_diagnostic = %Types.Diagnostic{
        message: diagnostic.message,
        range: lsp_range,
        severity: diagnostic.severity,
        source: diagnostic.source
      }

      {:ok, proto_diagnostic}
    end
  end

  def to_native(%Diagnostic.Result{} = diagnostic, _) do
    {:ok, diagnostic}
  end

  defp position_to_range(%Document{} = document, {start_line, start_column, end_line, end_column}) do
    with {:ok, start_pos} <- position_to_range(document, {start_line, start_column}),
         {:ok, end_pos} <- position_to_range(document, {end_line, end_column}) do
      {:ok, Document.Range.new(start_pos, end_pos)}
    end
  end

  defp position_to_range(%Document{} = document, {line_number, column}) do
    line_number = Math.clamp(line_number, 1, Document.size(document))
    column = max(column, 1)

    document
    |> to_lexical_range(line_number, column)
    |> Conversions.to_lsp(document)
  end

  defp position_to_range(document, line_number) when is_integer(line_number) do
    line_number = Math.clamp(line_number, 1, Document.size(document))

    with {:ok, line_text} <- Document.fetch_text_at(document, line_number) do
      column = Text.count_leading_spaces(line_text) + 1

      document
      |> to_lexical_range(line_number, column)
      |> Conversions.to_lsp(document)
    end
  end

  defp position_to_range(document, %Document.Range{} = range) do
    Conversions.to_lsp(range, document)
  end

  defp position_to_range(document, %Document.Position{} = position) do
    with {:ok, lsp_start_pos} <- Conversions.to_lsp(position, document) do
      range =
        Types.Range.new(
          start: lsp_start_pos,
          end: Types.Position.new(line: lsp_start_pos.line + 1, character: 0)
        )

      {:ok, range}
    end
  end

  defp to_lexical_range(%Document{} = document, line_number, column) do
    line_number = Math.clamp(line_number, 1, Document.size(document) + 1)

    Range.new(
      Position.new(document, line_number, column),
      Position.new(document, line_number + 1, 1)
    )
  end
end
