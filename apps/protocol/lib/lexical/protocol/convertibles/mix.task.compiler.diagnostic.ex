defimpl Lexical.Convertible, for: Mix.Task.Compiler.Diagnostic do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Math
  alias Lexical.Protocol.Conversions
  alias Lexical.Protocol.Types
  alias Lexical.Text
  alias Mix.Task.Compiler

  def to_lsp(%Compiler.Diagnostic{} = diagnostic, _context_document) do
    diagnostic_uri = Document.Path.ensure_uri(diagnostic.file)

    with {:ok, document} <- Document.Store.open_temporary(diagnostic_uri),
         {:ok, lsp_range} <- position_to_range(document, diagnostic.position) do
      proto_diagnostic = %Types.Diagnostic{
        message: diagnostic.message,
        range: lsp_range,
        severity: diagnostic.severity,
        source: "Elixir"
      }

      {:ok, proto_diagnostic}
    end
  end

  def to_native(%Compiler.Diagnostic{} = diagnostic, _) do
    {:ok, diagnostic}
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

  defp to_lexical_range(%Document{} = document, line_number, column) do
    line_number = Math.clamp(line_number, 1, Document.size(document) + 1)
    Range.new(Position.new(line_number, column), Position.new(line_number + 1, 1))
  end
end
