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

    with {:ok, source_file} <- Document.Store.open_temporary(diagnostic_uri),
         {:ok, lsp_range} <- position_to_range(source_file, diagnostic.position) do
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

  defp position_to_range(%Document{} = source_file, {line_number, column}) do
    line_number = Math.clamp(line_number, 1, Document.size(source_file))
    column = max(column, 1)

    source_file
    |> to_lexical_range(line_number, column)
    |> Conversions.to_lsp(source_file)
  end

  defp position_to_range(source_file, line_number) when is_integer(line_number) do
    line_number = Math.clamp(line_number, 1, Document.size(source_file))

    with {:ok, line_text} <- Document.fetch_text_at(source_file, line_number) do
      column = Text.count_leading_spaces(line_text) + 1

      source_file
      |> to_lexical_range(line_number, column)
      |> Conversions.to_lsp(source_file)
    end
  end

  defp to_lexical_range(%Document{} = source_file, line_number, column) do
    line_number = Math.clamp(line_number, 1, Document.size(source_file) + 1)
    Range.new(Position.new(line_number, column), Position.new(line_number + 1, 1))
  end
end
