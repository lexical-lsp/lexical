defmodule Lexical.RemoteControl.Tracer.ModuleParser do
  import NimbleParsec

  space = ascii_string([?\s], min: 1)

  begin_space = space |> unwrap_and_tag(:begin_space)

  alias_tag =
    optional(choice([string("alias"), string("require"), string("import")]))
    |> unwrap_and_tag(:alias_tag)

  space_after_alias_tag = space |> unwrap_and_tag(:space_after_alias_tag)

  single_module = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1)

  module_path = times(single_module |> concat(optional(string("."))), min: 1)

  defparsec(
    :parse,
    empty()
    |> concat(begin_space)
    |> concat(alias_tag)
    |> concat(space_after_alias_tag)
    |> concat(tag(module_path, :module_path))
  )

  optional_space = optional(space)
  parent_module_path = module_path |> tag(:parent_module_path)
  curly_bracket = string("{") |> concat(optional_space) |> unwrap_and_tag(:curly_bracket)
  child_splition = optional_space |> concat(string(",")) |> concat(optional_space)

  children = times(single_module |> concat(optional(child_splition)), min: 1) |> tag(:children)

  curly_bracket_terminator =
    optional_space |> concat(string("}")) |> unwrap_and_tag(:curly_bracket)

  defparsec(
    :parse_unexpanded_alias,
    empty()
    |> concat(begin_space)
    |> concat(alias_tag)
    |> concat(space_after_alias_tag)
    |> concat(parent_module_path)
    |> concat(curly_bracket)
    |> concat(optional(children))
    |> concat(curly_bracket_terminator)
  )

  def modules_at_cursor(line_text, column) do
    cond do
      unexpanded_alias?(line_text) ->
        search_when_unexpanded(line_text, column)

      as?(line_text, column) ->
        search_when_as(line_text)

      true ->
        search_when_referenced(line_text, column)
    end
  end

  defp unexpanded_alias?(line_text) do
    alias?(line_text) and String.contains?(line_text, "{")
  end

  defp alias?(line_text) do
    line_text |> String.trim() |> String.starts_with?(["alias ", "import ", "require "])
  end

  defp as?(line_text, column) do
    contains_as = line_text |> String.trim() |> String.contains?("as:")

    if contains_as do
      {as_start, _} = :binary.match(line_text, "as:")
      column > as_start + 1
    else
      false
    end
  end

  def search_when_referenced(line_text, column) do
    context = Code.Fragment.surround_context(line_text, {1, column})

    case context do
      %{begin: {_, start}, context: {:struct, struct}} ->
        ranges = struct |> List.to_string() |> split_module() |> list_ranges(start + 1)
        take_values_while(ranges, column)

      %{begin: {_, start}, context: {:alias, module}} ->
        ranges = module |> List.to_string() |> split_module() |> list_ranges(start)
        take_values_while(ranges, column)

      other ->
        other
    end
  end

  def search_when_as(line_text) do
    case parse(line_text) do
      {:ok, parsed, _, _, _, _} -> parsed[:module_path] |> trim_dot()
      other -> other
    end
  end

  def search_when_unexpanded(line_text, column) do
    case parse_unexpanded_alias(line_text) do
      {:ok, parsed, _, _, _, _} ->
        ranges = mapping_ranges(parsed)

        if tag_by(ranges, column) == :parent_module_path do
          parsed[:parent_module_path] |> trim_dot()
        else
          {start, _} = range_by_tag(ranges, :children)
          child = parsed[:children] |> list_ranges(start) |> find_value_in_range(column)

          if starts_with_upcase?(child) do
            parsed[:parent_module_path] ++ [child]
          else
            []
          end
        end

      other ->
        other
    end
  end

  defp tag_by(ranges, column) do
    Enum.find_value(ranges, fn {{label, _}, {start, end_}} ->
      if start <= column and column < end_ do
        label
      end
    end)
  end

  defp starts_with_upcase?(m) do
    m |> String.at(0) |> String.match?(~r/[A-Z]/)
  end

  defp trim_dot(module_path) do
    if List.last(module_path) == "." do
      List.delete_at(module_path, -1)
    else
      module_path
    end
  end

  defp range_by_tag(ranges, tag) do
    Enum.find_value(ranges, fn {{k, _v}, range} -> if k == tag, do: range end)
  end

  defp find_value_in_range(ranges, column) do
    Enum.find_value(ranges, fn {v, {start, end_}} ->
      if column >= start and column < end_, do: v
    end)
  end

  defp take_values_while(ranges, column) do
    ranges = Enum.reverse(ranges)

    ranges
    |> Enum.take_while(fn {_, {start, _}} ->
      column >= start
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp mapping_ranges(mapping) do
    {ranges, _} =
      for {tag, value} <- mapping, reduce: {[], 1} do
        {collected, n} ->
          end_ = n + value_length(value)
          new_collected = [{{tag, value}, {n, end_}} | collected]
          {new_collected, n + value_length(value)}
      end

    ranges
  end

  defp list_ranges(list, start) do
    {ranges, _} =
      for value <- list, reduce: {[], start} do
        {collected, n} ->
          end_ = n + value_length(value)
          new_collected = [{value, {n, end_}} | collected]
          {new_collected, n + value_length(value)}
      end

    ranges
  end

  defp value_length(value) when is_list(value), do: Enum.map(value, &value_length/1) |> Enum.sum()

  defp value_length(value) when is_binary(value), do: String.length(value)

  defp split_module(module_path) do
    String.split(module_path, ~r/\./, include_captures: true)
  end
end
