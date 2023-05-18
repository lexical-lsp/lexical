defmodule Lexical.Protocol.Diagnostic.Support do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Math
  alias Lexical.Protocol.Conversions
  alias Lexical.Text

  def position_to_range(%Document{} = document, {line_number, column}) do
    line_number = Math.clamp(line_number, 1, Document.size(document))
    column = max(column, 1)

    document
    |> to_lexical_range(line_number, column)
    |> Conversions.to_lsp(document)
  end

  def position_to_range(document, line_number) when is_integer(line_number) do
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
