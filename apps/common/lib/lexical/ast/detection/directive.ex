defmodule Lexical.Ast.Detection.Directive do
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  def detected?(%Document{} = document, %Position{} = position, directive_type) do
    document
    |> Tokens.prefix_stream(position)
    |> Enum.to_list()
    |> Enum.reduce_while(false, fn
      {:identifier, ^directive_type, _}, _ ->
        {:halt, true}

      {:eol, _, _}, _ ->
        {:halt, false}

      _, _ ->
        {:cont, false}
    end)
  end
end
