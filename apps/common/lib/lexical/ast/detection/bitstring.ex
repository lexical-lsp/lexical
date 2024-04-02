defmodule Lexical.Ast.Detection.Bitstring do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    document = analysis.document
    Document.fragment(document, Position.new(document, position.line, 1), position)

    document
    |> Tokens.prefix_stream(position)
    |> Enum.reduce_while(
      false,
      fn
        {:operator, :">>", _}, _ -> {:halt, false}
        {:operator, :"<<", _}, _ -> {:halt, true}
        _, _ -> {:cont, false}
      end
    )
  end
end
