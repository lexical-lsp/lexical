defmodule Lexical.Math do
  def clamp(number, min_number, max_number) do
    number |> max(min_number) |> min(max_number)
  end

  def count_leading_spaces(str), do: count_leading_spaces(str, 0)

  def count_leading_spaces(<<c::utf8, rest::binary>>, count) when c in [?\s, ?\t],
    do: count_leading_spaces(rest, count + 1)

  def count_leading_spaces(_, count), do: count
end
