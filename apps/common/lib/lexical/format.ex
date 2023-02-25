defmodule Lexical.Format do
  def seconds(time, opts \\ []) do
    units = Keyword.get(opts, :unit, :microsecond)
    millis = to_milliseconds(time, units)

    cond do
      millis >= 1000 ->
        "#{Float.round(millis / 1000, 1)} seconds"

      millis >= 1.0 ->
        "#{trunc(millis)} ms"

      true ->
        "#{millis} ms"
    end
  end

  def module(module_name) when is_atom(module_name) do
    string_name = Atom.to_string(module_name)

    if String.contains?(string_name, ".") do
      module_name
      |> Module.split()
      |> Enum.join(".")
    else
      # erlang module_name
      ":#{string_name}"
    end
  end

  def module_name(module_name) when is_binary(module_name) do
    module_name
  end

  defp to_milliseconds(micros, :microsecond) do
    micros / 1000
  end

  defp to_milliseconds(millis, :millisecond) do
    millis
  end
end
