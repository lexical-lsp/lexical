defimpl Lexical.Convertible, for: Mix.Task.Compiler.Diagnostic do
  alias Lexical.Protocol.Conversions
  alias Lexical.Math
  alias Lexical.Protocol.Types
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range
  alias Mix.Task.Compiler
  alias Lexical.Text

  def to_lsp(%Compiler.Diagnostic{} = diagnostic, _context_document) do
    diagnostic_uri = SourceFile.Path.ensure_uri(diagnostic.file)

    with {:ok, source_file} <- SourceFile.Store.open_temporary(diagnostic_uri),
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

  defp position_to_range(%SourceFile{} = source_file, {line_number, column}) do
    line_number = Math.clamp(line_number, 1, SourceFile.size(source_file))
    column = max(column, 1)

    source_file
    |> to_lexical_range(line_number, column)
    |> Conversions.to_lsp(source_file)
  end

  defp position_to_range(source_file, line_number) when is_integer(line_number) do
    line_number = Math.clamp(line_number, 1, SourceFile.size(source_file))

    with {:ok, line_text} <- SourceFile.fetch_text_at(source_file, line_number) do
      column = Text.count_leading_spaces(line_text) + 1

      source_file
      |> to_lexical_range(line_number, column)
      |> Conversions.to_lsp(source_file)
    end
  end

  defp to_lexical_range(%SourceFile{} = source_file, line_number, column) do
    line_number = Math.clamp(line_number, 1, SourceFile.size(source_file) + 1)
    Range.new(Position.new(line_number, column), Position.new(line_number + 1, 1))
  end
end
