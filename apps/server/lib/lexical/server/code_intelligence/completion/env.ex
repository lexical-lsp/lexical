defmodule Lexical.Server.CodeIntelligence.Completion.Env do
  alias Lexical.Completion.Builder
  alias Lexical.Completion.Environment
  alias Lexical.Document
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Server.CodeIntelligence.Completion.Env

  defstruct [
    :project,
    :document,
    :line,
    :prefix,
    :suffix,
    :position,
    :words,
    :zero_based_character
  ]

  @type t :: %__MODULE__{
          project: Lexical.Project.t(),
          document: Lexical.Document.t(),
          prefix: String.t(),
          suffix: String.t(),
          position: Lexical.Document.Position.t(),
          words: [String.t()],
          zero_based_character: non_neg_integer()
        }

  @behaviour Environment

  def new(%Project{} = project, %Document{} = document, %Position{} = cursor_position) do
    case Document.fetch_text_at(document, cursor_position.line) do
      {:ok, line} ->
        zero_based_character = cursor_position.character - 1
        graphemes = String.graphemes(line)
        prefix = graphemes |> Enum.take(zero_based_character) |> IO.iodata_to_binary()
        suffix = String.slice(line, zero_based_character..-1)
        words = String.split(prefix)

        {:ok,
         %__MODULE__{
           document: document,
           line: line,
           position: cursor_position,
           prefix: prefix,
           project: project,
           suffix: suffix,
           words: words,
           zero_based_character: zero_based_character
         }}

      _ ->
        {:error, :out_of_bounds}
    end
  end

  @impl Environment
  def prefix_tokens(%__MODULE__{} = env, count \\ :all) do
    line_charlist = String.to_charlist(env.prefix)

    tokens =
      case :elixir_tokenizer.tokenize(line_charlist, 1, 1, []) do
        {:ok, _, _, _, tokens} ->
          Enum.reverse(tokens)

        {:error, _, _, _, reversed_tokens} ->
          reversed_tokens
      end

    take_relevant_tokens(tokens, [], env.position.character, count)
  end

  @impl Environment
  def function_capture?(%__MODULE__{} = env) do
    env
    |> prefix_tokens()
    |> Enum.reduce_while(false, fn
      {:paren, :")"}, _ ->
        {:halt, false}

      {:operator, :&}, _ ->
        {:halt, true}

      {:int, _} = maybe_arity, _ ->
        {:cont, maybe_arity}

      {:operator, :/}, {:int, _} ->
        # if we encounter a trailing /<arity> in the prefix, the
        # function capture is complete, and we're not inside it
        {:halt, false}

      _, _ ->
        {:cont, false}
    end)
  end

  @impl Environment
  def struct_reference?(%__MODULE__{} = env) do
    case cursor_context(env) do
      {:ok, _line, {:struct, _}} ->
        true

      {:ok, line, {:local_or_var, [?_, ?_ | rest]}} ->
        # a reference to `%__MODULE`, often in a function head, as in
        # def foo(%__)
        String.starts_with?("MODULE", List.to_string(rest)) and String.contains?(line, "%__")

      _ ->
        false
    end
  end

  @impl Environment
  def pipe?(%__MODULE__{} = env) do
    with {:ok, line, context} <- surround_context(env),
         {:ok, {:operator, '|>'}} <- previous_surround_context(line, context) do
      true
    else
      _ ->
        false
    end
  end

  @impl Environment
  def in_bitstring?(%__MODULE__{} = env) do
    env
    |> prefix_tokens(:all)
    |> Enum.reduce_while(
      false,
      fn
        {:operator, :">>"}, _ -> {:halt, false}
        {:operator, :"<<"}, _ -> {:halt, true}
        _, _ -> {:cont, false}
      end
    )
  end

  @impl Environment
  def empty?("") do
    true
  end

  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end

  @impl Environment
  def last_word(%__MODULE__{} = env) do
    List.last(env.words)
  end

  @behaviour Builder

  @impl Builder
  def snippet(%Env{}, snippet_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, snippet_text)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
  end

  @impl Builder
  def plain_text(%Env{}, insert_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, insert_text)
    |> Completion.Item.new()
  end

  @impl Builder
  def text_edit(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    line_number = env.position.line
    range = Range.new(Position.new(line_number, start_char), Position.new(line_number, end_char))
    edits = Document.Changes.new(env.document, Edit.new(text, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Completion.Item.new()
  end

  @impl Builder
  def text_edit_snippet(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    line_number = env.position.line
    range = Range.new(Position.new(line_number, start_char), Position.new(line_number, end_char))
    edits = Document.Changes.new(env.document, Edit.new(text, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
  end

  @impl Builder
  def fallback(nil, fallback), do: fallback
  def fallback("", fallback), do: fallback
  def fallback(detail, _), do: detail

  @impl Builder
  def boost(text, amount \\ 5)

  def boost(text, amount) when amount in 0..10 do
    boost_char = ?* - amount
    IO.iodata_to_binary([boost_char, text])
  end

  def boost(text, _) do
    boost(text, 0)
  end

  # private

  defp cursor_context(%__MODULE__{} = env) do
    with {:ok, line} <- Document.fetch_text_at(env.document, env.position.line) do
      fragment = String.slice(line, 0..(env.zero_based_character - 1))
      {:ok, line, Code.Fragment.cursor_context(fragment)}
    end
  end

  defp surround_context(%__MODULE__{} = env) do
    with {:ok, line} <- Document.fetch_text_at(env.document, env.position.line),
         %{context: _} = context <-
           Code.Fragment.surround_context(line, {1, env.zero_based_character}) do
      {:ok, line, context}
    end
  end

  defp previous_surround_context(line, %{begin: {1, column}}) do
    previous_surround_context(line, column)
  end

  defp previous_surround_context(_line, 1) do
    :error
  end

  defp previous_surround_context(line, character) when is_integer(character) do
    case Code.Fragment.surround_context(line, {1, character - 1}) do
      :none ->
        previous_surround_context(line, character - 1)

      %{context: context} ->
        {:ok, context}
    end
  end

  defp take_relevant_tokens([], tokens, _, _) do
    Enum.reverse(tokens)
  end

  defp take_relevant_tokens(_, tokens, _, 0) do
    Enum.reverse(tokens)
  end

  defp take_relevant_tokens([token | rest], tokens, start_character, remaining) do
    remaining = decrement(remaining)
    take_relevant_tokens(rest, [normalize_token(token) | tokens], start_character, remaining)
  end

  defp normalize_token(token) do
    case token do
      {:capture_op, _context, value} ->
        {:operator, value}

      {:dual_op, _context, value} ->
        {:operator, value}

      {:type_op, _context, _value} ->
        {:operator, :"::"}

      {:bin_string, _, value} ->
        {:string, List.to_string(value)}

      {:operator, _, value} ->
        {:operator, value}

      {type, {_, _, nil}, value} when is_list(value) ->
        {normalize_type(type), value}

      {type, {_, _, token_value}, _} ->
        {normalize_type(type), token_value}

      {type, _context, value} when is_atom(value) ->
        {normalize_type(type), value}

      {operator, _} ->
        {map_operator(operator), operator}
    end
  end

  defp decrement(:all), do: :all
  defp decrement(num) when is_integer(num), do: num - 1

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
