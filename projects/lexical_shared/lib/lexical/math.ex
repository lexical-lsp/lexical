defmodule Lexical.Math do
  @moduledoc """
  Utilities related to mathematical operations
  """

  @doc """
  Clamp the number between `min_number` and `max_number`

  If the first argument is less than `min_number`, then `min_number` is returned.

  If the number given in the first argument is greater than `max_number` then `max_number` is returned.

  Otherwise, the first argument is returned.
  """
  def clamp(number, min_number, max_number)
      when is_number(number) and is_number(min_number) and is_number(max_number) do
    number |> max(min_number) |> min(max_number)
  end
end
