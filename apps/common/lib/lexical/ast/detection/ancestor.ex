defmodule Lexical.Ast.Detection.Ancestor do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Position

  def is_def?(%Document{} = document, %Position{} = position) do
    document
    |> Ast.cursor_path(position)
    |> Enum.any?(fn
      {:def, _, _} ->
        true

      {:defp, _, _} ->
        true

      _ ->
        false
    end)
  end

  @type_keys [:type, :typep, :opaque]
  def is_type?(%Document{} = document, %Position{} = position) do
    document
    |> Ast.cursor_path(position)
    |> Enum.any?(fn
      {:@, metadata, [{type_key, _, _}]} when type_key in @type_keys ->
        # single line type
        cursor_in_range?(position, metadata)

      {:__block__, _, [{:@, metadata, [{type_key, _, _}]}, _]}
      when type_key in @type_keys ->
        # multi-line type
        cursor_in_range?(position, metadata)

      _ ->
        false
    end)
  end

  def is_spec?(%Document{} = document, %Position{} = position) do
    document
    |> Ast.cursor_path(position)
    |> Enum.any?(fn
      {:@, metadata, [{:spec, _, _}]} ->
        # single line spec
        cursor_in_range?(position, metadata)

      {:__block__, _, [{:@, metadata, [{:spec, _, _}]}, _]} ->
        # multi-line spec
        cursor_in_range?(position, metadata)

      _ ->
        false
    end)
  end

  defp cursor_in_range?(position, metadata) do
    expression_end_line = get_in(metadata, [:end_of_expression, :line])
    expression_end_column = get_in(metadata, [:end_of_expression, :column])
    cursor_line = position.line
    cursor_column = position.character

    if cursor_line == expression_end_line do
      expression_end_column > cursor_column
    else
      cursor_line < expression_end_line
    end
  end
end
