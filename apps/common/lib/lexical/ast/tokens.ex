defmodule Lexical.Ast.Tokens do
  alias Lexical.Document
  alias Lexical.Document.Position

  @doc """
  Returns a stream of tokens starting at the given position and working backwards through
  the document.
  """
  def prefix_stream(%Document{} = document, %Position{} = position) do
    init_function = fn ->
      {~c"", position.line}
    end

    next_function = fn
      {_, 0} ->
        {:halt, []}

      {current_context, line_number} ->
        case find_and_tokenize(document, position, line_number, current_context) do
          {:ok, tokens, new_context} ->
            prev_line_number = line_number - 1

            tokens =
              if prev_line_number > 0 do
                tokens ++ [:eol]
              else
                tokens
              end

            {tokens, {new_context, prev_line_number}}

          :stop ->
            {:halt, []}
        end
    end

    finalize_function = fn _ -> :ok end

    init_function
    |> Stream.resource(next_function, finalize_function)
    |> Stream.map(&normalize_token/1)
  end

  defp find_and_tokenize(
         %Document{} = document,
         %Position{line: line_number} = position,
         line_number,
         context
       ) do
    document
    |> prefix(position)
    |> tokenize(line_number, context)
  end

  defp find_and_tokenize(%Document{} = document, %Position{}, line_number, context) do
    case Document.fetch_text_at(document, line_number) do
      {:ok, line_text} ->
        tokenize(line_text, line_number, context)

      :error ->
        :stop
    end
  end

  defp tokenize(line_text, line_number, context) do
    line_charlist = String.to_charlist(line_text)
    current_context = line_charlist ++ context

    case :future_elixir_tokenizer.tokenize(current_context, line_number, 1, []) do
      {:ok, _, _, _, tokens} ->
        {:ok, Enum.reverse(tokens), ~c""}

      {:error, {_, _, ~c"unexpected token: ", _}, _, _, _} ->
        {:ok, [], ~c"\n" ++ current_context}

      {:error, _, _, _, tokens} ->
        {:ok, tokens, ~c""}
    end
  end

  defp prefix(%Document{} = document, %Position{} = position) do
    zero_based_character = position.character - 1
    {:ok, line_text} = Document.fetch_text_at(document, position.line)
    String.slice(line_text, 0, zero_based_character)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp normalize_token(token) do
    case token do
      :eol ->
        {:eol, ~c"\n", []}

      {:bin_string, context, [string_value]} ->
        {:string, string_value, to_position(context)}

      {:bin_string, context, interpolated} ->
        {:interpolated_string, interpolated, to_position(context)}

      {:capture_op, context, value} ->
        {:operator, value, to_position(context)}

      {:dual_op, context, value} ->
        {:operator, value, to_position(context)}

      {:type_op, context, _value} ->
        {:operator, :"::", to_position(context)}

      {:mult_op, context, operator} ->
        {:operator, operator, to_position(context)}

      {:in_op, context, _} ->
        {:operator, :in, to_position(context)}

      {:operator, context, value} ->
        {:operator, value, to_position(context)}

      {:sigil, {line, column, _}, sigil_char, _sigil_context, _, _opts, delim} ->
        # NOTE: should we need to return context too?
        {:sigil, [sigil_char], {line, column}, delim}

      {type, {line, column, token_value}, _} ->
        {normalize_type(type), token_value, {line, column}}

      {type, context, value} when is_atom(value) ->
        {normalize_type(type), value, to_position(context)}

      {operator, context} ->
        {map_operator(operator), operator, to_position(context)}
    end
  end

  defp to_position({line, column, _}) do
    {line, column}
  end

  defp map_operator(:"("), do: :paren
  defp map_operator(:")"), do: :paren
  defp map_operator(:"{"), do: :curly
  defp map_operator(:"}"), do: :curly
  defp map_operator(:","), do: :comma
  defp map_operator(:%{}), do: :map_new
  defp map_operator(:%), do: :percent
  defp map_operator(_), do: :operator

  defp normalize_type(:flt), do: :float
  defp normalize_type(:bin_string), do: :string
  defp normalize_type(type), do: type
end
