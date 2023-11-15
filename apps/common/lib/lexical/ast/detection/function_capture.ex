defmodule Lexical.Ast.Detection.FunctionCapture do
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    document
    |> Tokens.prefix_stream(position)
    |> Enum.reduce_while(false, fn
      {:paren, :")", _}, _ ->
        {:halt, false}

      {:operator, :&, _}, _ ->
        {:halt, true}

      {:int, _, _} = maybe_arity, _ ->
        {:cont, maybe_arity}

      {:operator, :/, _}, {:int, _, _} ->
        # if we encounter a trailing /<arity> in the prefix, the
        # function capture is complete, and we're not inside it
        {:halt, false}

      _, _ ->
        {:cont, false}
    end)
  end
end
