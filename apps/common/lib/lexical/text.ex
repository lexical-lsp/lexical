defmodule Lexical.Text do
  def count_leading_spaces(str), do: count_leading_spaces(str, 0)

  def count_leading_spaces(<<c, rest::binary>>, count) when c in [?\s, ?\t],
    do: count_leading_spaces(rest, count + 1)

  def count_leading_spaces(_, count), do: count
end
