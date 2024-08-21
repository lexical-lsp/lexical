defmodule Lexical.Ast.Detection.Directive do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Tokens
  alias Lexical.Document.Position

  @doc """
  Recognizes a directive (`alias`/`require`/`import`/`use`) at the current position.
  """
  def detected?(%Analysis{} = analysis, %Position{} = position, directive_type) do
    analysis.document
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
