defmodule Lexical.Ast.Callable do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Sourceror.Zipper

  import Sourceror.Identifier, only: [is_call: 1]

  def fetch_name_range(%Analysis{} = analysis, %Position{} = position, name) do
    fetch_name_range(analysis.document, position, name)
  end

  def fetch_name_range(%Document{} = document, %Position{} = position, name) do
    case Ast.zipper_at(document, position) do
      {:ok, %Zipper{node: node} = zipper} when is_call(node) ->
        {_, name_range} =
          Zipper.traverse_while(zipper, nil, fn
            %Zipper{node: {{:., _meta, [_aliases, ^name]}, _, _} = node} = zipper, _acc ->
              {:halt, zipper, name_range(node, position)}

            %Zipper{node: {^name, _meta, _params_and_body} = node} = zipper, _acc ->
              {:halt, zipper, name_range(node, position)}

            zipper, _acc ->
              {:cont, zipper, nil}
          end)

        if name_range do
          {:ok, name_range}
        else
          :error
        end

      {:ok, zipper} ->
        {:ok, name_range(zipper.node, position)}

      _ ->
        {:error, :not_a_callable}
    end
  end

  defp name_range({{:., meta, [_aliases, callable_name]}, _, _}, position) do
    dot_length = 1
    start_character = meta[:column] + dot_length
    callable_name = to_string(callable_name)
    end_character = start_character + String.length(callable_name)

    start_position = %{position | character: start_character}
    end_position = %{position | character: end_character}
    Range.new(start_position, end_position)
  end

  defp name_range({callable_name, meta, _params_and_body}, position)
       when is_atom(callable_name) do
    callable_name = to_string(callable_name)
    start_position = %{position | character: meta[:column]}
    end_position = %{position | character: meta[:column] + String.length(callable_name)}
    Range.new(start_position, end_position)
  end
end
