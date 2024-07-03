defmodule Lexical.Formats do
  @moduledoc """
  A collection of formatting functions
  """

  @type unit :: :millisecond | :second
  @type time_opt :: {:unit, unit}
  @type time_opts :: [time_opt]

  @doc """
  Formats an elapsed time to either seconds or milliseconds

  Examples:

  ```
  Format.seconds(500, unit: :millisecond)
  "0.5 seconds"
  ```

  ```
  Format.format(1500, unit: :millisecond)
  "1.4 seconds"
  ```

  ```
  Format.format(1500)
  "15 ms"
  ```
  """
  @spec time(time :: non_neg_integer(), opts :: time_opts) :: String.t()
  def time(time, opts \\ []) do
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

  @doc """
  Formats a name of a module
  Both elixir and erlang modules will format like they appear in elixir source code.

  ```
   Format.format(MyModule)
   "MyModule"
   ```

   ```
  Formats.module(Somewhat.Nested.Module)
  "Somewhat.Nested.Module"
  ```

  ```
  Format.format(:erlang_module)
  ":erlang_module"
  ```
  """
  @spec module(atom()) :: String.t()
  def module(module_name) when is_atom(module_name) do
    string_name = Atom.to_string(module_name)

    if String.contains?(string_name, ".") do
      case string_name do
        "Elixir." <> rest -> rest
        other -> other
      end
    else
      # erlang module_name
      ":#{string_name}"
    end
  end

  def module(module_name) when is_binary(module_name) do
    module_name
  end

  defp to_milliseconds(micros, :microsecond) do
    micros / 1000
  end

  defp to_milliseconds(millis, :millisecond) do
    millis
  end

  def plural(count, singular, plural) do
    case count do
      0 -> templatize(count, plural)
      1 -> templatize(count, singular)
      _n -> templatize(count, plural)
    end
  end

  def mfa(module, function, arity) do
    "#{module(module)}.#{function}/#{arity}"
  end

  defp templatize(count, template) do
    count_string = Integer.to_string(count)
    String.replace(template, "${count}", count_string)
  end
end
