defmodule Lexical.Text do
  def format_seconds(time, opts \\ []) do
    units = Keyword.get(opts, :unit, :microsecond)
    millis = to_milliseconds(time, units)

    cond do
      millis > 1000 ->
        "#{Float.round(millis / 1000, 1)} seconds"

      true ->
        "#{millis} ms"
    end
  end

  def module_name(module_name) when is_atom(module_name) do
    module_name
    |> Module.split()
    |> Enum.join(".")
  end

  def module_name(module_name) when is_binary(module_name) do
    module_name
  end

  defp to_milliseconds(micros, :microsecond) do
    round(micros / 1000)
  end

  defp to_milliseconds(millis, :millisecond) do
    millis
  end
end
