defmodule Lexical.Ast.Detection.String do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Document.Position
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  use Detection

  @string_sigils [
    :sigil_s,
    :sigil_S
  ]

  @impl Detection
  def detected?(%Analysis{} = analysis, %Position{} = position) do
    case Ast.path_at(analysis, position) do
      {:ok, path} ->
        detect_string(path, position)

      _ ->
        false
    end
  end

  defp detect_string(paths, %Position{} = position) do
    {_, detected?} =
      Macro.postwalk(paths, false, fn
        ast, false ->
          detected? = do_detect(ast, position)
          {ast, detected?}

        ast, true ->
          {ast, true}
      end)

    detected?
  end

  # a string literal
  defp do_detect({:__block__, _, [literal]} = ast, %Position{} = position)
       when is_binary(literal) do
    ast
    |> ast_to_range(0, -1)
    |> Range.contains?(position)
  end

  # a possible string with interpolation
  defp do_detect({:<<>>, meta, _} = ast, %Position{} = position) do
    # this might also be a binary match / construction
    Keyword.has_key?(meta, :delimiter) and detect_interpolation(ast, position)
  end

  # String sigils
  defp do_detect({sigil, _, _} = ast, %Position{} = position)
       when sigil in @string_sigils do
    ast
    |> ast_to_range(0, 0)
    |> Range.contains?(position)
  end

  defp do_detect(_, _),
    do: false

  # a string with interpolation
  defp detect_interpolation(
         {:<<>>, meta, interpolations} = ast,
         %Position{} = position
       ) do
    delimiter_length =
      meta
      |> Keyword.get(:delimiter, "\"")
      |> String.length()

    string_range = ast_to_range(ast, delimiter_length, -1)
    interpolation_ranges = collect_interpolation_ranges(interpolations)

    Range.contains?(string_range, position) and
      not Enum.any?(interpolation_ranges, &Range.contains?(&1, position))
  end

  defp collect_interpolation_ranges(interpolations) do
    {_, acc} =
      Macro.prewalk(interpolations, [], fn
        {:"::", _, _} = interpolation, acc ->
          range = ast_to_range(interpolation, 1, -1)

          {interpolation, [range | acc]}

        ast, acc ->
          {ast, acc}
      end)

    acc
  end
end
