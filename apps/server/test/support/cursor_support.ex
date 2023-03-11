defmodule Lexical.Test.CursorSupport do
  def cursor_position(text) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({0, 0}, fn
      "|", line_and_column ->
        {:halt, line_and_column}

      "\n", {line, _} ->
        {:cont, {line + 1, 0}}

      _, {line, column} ->
        {:cont, {line, column + 1}}
    end)
  end
end
