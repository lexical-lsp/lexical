defmodule Lexical.RemoteControl.CodeIntelligence.Definition do
  alias Future.Code, as: Code
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.Text

  def definition(%Document{} = document, %Position{} = position) do
    document
    |> Document.to_string()
    |> ElixirSense.definition(position.line, position.character)
    |> parse_location(document)
  end

  defp parse_location(%ElixirSense.Location{} = location, document) do
    %{file: file, line: line, column: column, type: type} = location
    file_path = file || document.path
    uri = Document.Path.ensure_uri(file_path)

    with {:ok, document} <- Document.Store.open_temporary(uri),
         {:ok, text} <- Document.fetch_text_at(document, line) do
      {line, column} = maybe_move_cursor_to_next(type, document, line, column)
      range = to_precise_range(document, text, line, column)
      {:ok, Location.new(range, document)}
    else
      _ ->
        {:error, "Could not open source file or fetch line text: #{inspect(file_path)}"}
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp maybe_move_cursor_to_next(type, document, line, column)
       when type in [:function, :module, :macro] do
    position = Position.new(document, line, column)

    case Ast.zipper_at(document, position) do
      {:ok, zipper} ->
        zipper = %{node: {entity_name, meta, _}} = Sourceror.Zipper.next(zipper)

        if entity_name == :when do
          %{node: {_entity_name, meta, _}} = Sourceror.Zipper.next(zipper)
          {meta[:line], meta[:column]}
        else
          {meta[:line], meta[:column]}
        end

      _ ->
        {line, column}
    end
  end

  defp maybe_move_cursor_to_next(_, _, line, column), do: {line, column}

  defp to_precise_range(%Document{} = document, text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        Entity.to_range(document, start_pos, end_pos)

      _ ->
        # If the column is 1, but the code doesn't start on the first column, which isn't what we want.
        # The cursor will be placed to the left of the actual definition.
        column = if column == 1, do: Text.count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        Entity.to_range(document, pos, pos)
    end
  end
end
