defmodule Lexical.RemoteControl.Build.ErrorSupport do
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
end
