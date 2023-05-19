defmodule PluggedCredoProject do
  @moduledoc false

  def filter_x_and_a do
    ["a", "b", "c"]
    |> Enum.filter(&String.contains?(&1, "x"))
    |> Enum.filter(&String.contains?(&1, "a"))
  end
end
