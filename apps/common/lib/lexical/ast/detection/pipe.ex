defmodule Lexical.Ast.Detection.Pipe do
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    # Document.fragment(document, Position.new(document, position.line, 1), position)
    # |> IO.inspect()

    document
    |> Tokens.prefix_stream(position)
    |> Enum.to_list()
    #    |> IO.inspect()
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
