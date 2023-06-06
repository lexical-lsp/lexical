defmodule Lexical.Ast do
  alias Future.Code, as: Code
  alias Lexical.Document
  alias Lexical.Document.Position

  @doc """
  Returns the path to the cursor in the given document and position.
  """
  def cursor_path(%Document{} = doc, {line, character}) do
    cursor_path(doc, Position.new(line, character))
  end

  def cursor_path(%Document{} = document, %Position{} = position) do
    fragment = Document.fragment(document, position)

    case Code.Fragment.container_cursor_to_quoted(fragment, columns: true) do
      {:ok, quoted} ->
        quoted
        |> Future.Macro.path(&match?({:__cursor__, _, _}, &1))
        |> List.wrap()

      _ ->
        []
    end
  end
end
