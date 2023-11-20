defmodule Lexical.Ast.Detection.Pipe do
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    document
    |> Tokens.prefix_stream(position)
    |> Enum.to_list()
    |> Enum.reduce_while(false, fn
      {:identifier, _, _}, _ ->
        {:cont, false}

      {:operator, :., _}, _ ->
        {:cont, false}

      {:alias, _, _}, _ ->
        {:cont, false}

      {:arrow_op, nil, _}, _ ->
        {:halt, true}

      {:atom, _, _}, _ ->
        {:cont, false}

      _, _acc ->
        {:halt, false}
    end)
  end
end
