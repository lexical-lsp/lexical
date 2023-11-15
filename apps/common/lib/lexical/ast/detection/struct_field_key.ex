defmodule Lexical.Ast.Detection.StructFieldKey do
  alias Lexical.Ast
  alias Lexical.Ast.Detection
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    cursor_path = Ast.cursor_path(document, position)

    match?(
      # in the key position, the cursor will always be followed by the
      # map node because, in any other case, there will minimally be a
      # 2-element key-value tuple containing the cursor
      [{:__cursor__, _, _}, {:%{}, _, _}, {:%, _, _} | _],
      cursor_path
    )
  end
end
