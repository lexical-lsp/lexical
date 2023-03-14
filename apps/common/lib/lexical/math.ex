defmodule Lexical.Math do
  def clamp(number, min_number, max_number) do
    number |> max(min_number) |> min(max_number)
  end
end
