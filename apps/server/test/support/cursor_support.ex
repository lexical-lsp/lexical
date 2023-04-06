defmodule Lexical.Test.CursorSupport do
  def cursor_position(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.reduce_while({starting_line(), starting_column()}, fn
      ["|", ">"], {line, column} ->
        {:cont, {line, column + 1}}

      ["|", _], position ->
        {:halt, position}

      ["\n", _], {line, _column} ->
        {:cont, {line + 1, starting_column()}}

      _, {line, column} ->
        {:cont, {line, column + 1}}
    end)
  end

  def context_before_cursor(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.reduce_while([], fn
      ["|", ">"], iodata ->
        {:cont, [iodata, "|"]}

      ["|", _lookahead], iodata ->
        {:halt, iodata}

      [c, _], iodata ->
        {:cont, [iodata, c]}
    end)
    |> IO.iodata_to_binary()
  end

  def strip_cursor(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.reduce([], fn
      ["|", ">"], iodata ->
        [iodata, "|"]

      ["|", _lookahead], iodata ->
        iodata

      [c, _], iodata ->
        [iodata, c]
    end)
    |> IO.iodata_to_binary()
  end

  defp starting_line do
    1
  end

  defp starting_column do
    1
  end
end
