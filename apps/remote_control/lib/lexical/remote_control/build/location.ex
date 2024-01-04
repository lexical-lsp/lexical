defmodule Lexical.RemoteControl.Build.Location do
  alias Lexical.Plugin.V1.Diagnostic.Result

  def context_to_position(context) do
    cond do
      Keyword.has_key?(context, :line) and Keyword.has_key?(context, :column) ->
        position(context[:line], context[:column])

      Keyword.has_key?(context, :line) ->
        position(context[:line])

      true ->
        nil
    end
  end

  def position(line) do
    line
  end

  def position({line, column}, {end_line, end_column}) do
    {line, column, end_line, end_column}
  end

  def position(line, column) do
    {line, column}
  end

  def position(line, column, end_line, end_column) do
    {line, column, end_line, end_column}
  end

  def uniq(diagnostics) do
    exacts =
      Enum.filter(diagnostics, fn diagnostic -> match?({_, _, _, _}, diagnostic.position) end)

    extract_line = fn
      %Result{position: {line, _column}} -> line
      %Result{position: line} -> line
    end

    # Note: Sometimes error and warning appear on one line at the same time
    # So we need to uniq by line and severity,
    # and :error is always more important than :warning
    extract_line_and_severity = &{extract_line.(&1), &1.severity}

    filtered =
      diagnostics
      |> Enum.filter(fn diagnostic -> not match?({_, _, _, _}, diagnostic.position) end)
      |> Enum.sort_by(extract_line_and_severity)
      |> Enum.uniq_by(extract_line)
      |> reject_zeroth_line()

    exacts ++ filtered
  end

  defp reject_zeroth_line(diagnostics) do
    # Since 1.15, Elixir has some nonsensical error on line 0,
    # e.g.: Can't compile this file
    # We can simply ignore it, as there is a more accurate one
    Enum.reject(diagnostics, fn diagnostic ->
      diagnostic.position == 0
    end)
  end
end
