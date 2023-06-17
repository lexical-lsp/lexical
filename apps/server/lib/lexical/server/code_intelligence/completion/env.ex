defmodule Lexical.Server.CodeIntelligence.Completion.Env do
  alias Future.Code, as: Code
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

  import Document.Line

  defstruct [
    :project,
    :document,
    :line,
    :prefix,
    :suffix,
    :position,
    :zero_based_character
  ]

  @type t :: %__MODULE__{
          project: Lexical.Project.t(),
          document: Lexical.Document.t(),
          prefix: String.t(),
          suffix: String.t(),
          position: Lexical.Document.Position.t(),
          zero_based_character: non_neg_integer()
        }

  @behaviour Environment
  def new(%Project{} = project, %Document{} = document, %Position{} = cursor_position) do
    zero_based_character = cursor_position.character - 1

    case Document.fetch_text_at(document, cursor_position.line) do
      {:ok, line} ->
        prefix = String.slice(line, 0, zero_based_character)
        suffix = String.slice(line, zero_based_character..-1)

        env = %__MODULE__{
          document: document,
          line: line,
          position: cursor_position,
          prefix: prefix,
          project: project,
          suffix: suffix,
          zero_based_character: zero_based_character
        }

        {:ok, env}

      _ ->
        {:error, {:out_of_bounds, cursor_position}}
    end
  end

  @impl Environment
  def prefix_tokens(%__MODULE__{} = env, count \\ :all) do
    case count do
      :all ->
        prefix_token_stream(env)

      count when is_integer(count) ->
        env
        |> prefix_token_stream()
        |> Enum.take(count)
    end
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :function_capture) do
    env
    |> prefix_token_stream()
    |> Enum.reduce_while(false, fn
      {:paren, :")", _}, _ ->
        {:halt, false}

      {:operator, :&, _}, _ ->
        {:halt, true}

      {:int, _, _} = maybe_arity, _ ->
        {:cont, maybe_arity}

      {:operator, :/, _}, {:int, _, _} ->
        # if we encounter a trailing /<arity> in the prefix, the
        # function capture is complete, and we're not inside it
        {:halt, false}

      _, _ ->
        {:cont, false}
    end)
  end

  @impl Environment

  def in_context?(%__MODULE__{} = env, :struct_reference) do
    case cursor_context(env) do
      {:ok, _line, {:struct, _}} ->
        true

      {:ok, _line, {:local_or_var, [?_ | _rest]}} ->
        # a reference to `%__MODULE`, often in a function head, as in
        # def foo(%__)

        starts_with_percent? =
          env
          |> prefix_tokens(2)
          |> Enum.any?(fn
            {:percent, :%, _} -> true
            _ -> false
          end)

        starts_with_percent? and (ancestor_is_def?(env) or ancestor_is_type?(env))

      _ ->
        false
    end
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :struct_arguments) do
    env
    |> cursor_path()
    |> Enum.find_value(false, fn
      {:%, _, [{:__aliases__, _, _aliases} | _]} -> true
      {:%, _, [{:__MODULE__, _, _} | _]} -> true
      _ -> false
    end)
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :value) do
    env
    |> prefix_tokens(2)
    |> Enum.find_value(false, fn
      {:kw_identifier, _, _} -> true
      _ -> false
    end)
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :pipe) do
    env
    |> prefix_token_stream()
    |> Enum.reduce_while(false, fn
      {:identifier, _, _}, _ ->
        {:cont, false}

      {:operator, :., _}, _ ->
        {:cont, false}

      {:alias, _, _}, _ ->
        {:cont, false}

      {:arrow_op, nil, _}, _ ->
        {:halt, true}

      _x, _acc ->
        {:halt, false}
    end)
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :bitstring) do
    env
    |> prefix_tokens(:all)
    |> Enum.reduce_while(
      false,
      fn
        {:operator, :">>", _}, _ -> {:halt, false}
        {:operator, :"<<", _}, _ -> {:halt, true}
        _, _ -> {:cont, false}
      end
    )
  end

  @impl Environment

  def in_context?(%__MODULE__{} = env, :alias) do
    # Aliases are complicated, especially if we're trying to find out if we're in
    # them from the current cursor position moving backwards.
    # I'll try to describe the state machine below.
    # First off, if we're outside of a } on the current line, we cannot be in an alias, so that
    # halts with false.
    # Similarly an alias on the current line is also simple, we just backtrack until we see the alias identifier.
    # However, if we're on the current line, and see an EOL, we set that as our accumulator, then we get
    # to the previous line, we see if it ends in a comma. If not, we can't be in an alias. If it does, we keep
    # backtracking until we hit the alias keyword.
    # So basically, if we hit an EOL, and the previous token isn't an open curly or a comma, we stop, otherwise
    # we backtrack until we hit the alias keyword

    env
    |> prefix_token_stream()
    |> Stream.with_index()
    |> Enum.reduce_while(false, fn
      {{:curly, :"{", _}, _index}, :eol ->
        {:cont, false}

      {{:comma, _, _}, _index}, :eol ->
        {:cont, false}

      {{:eol, _, _}, _index}, _acc ->
        {:cont, :eol}

      {{_, _, _}, _}, :eol ->
        {:halt, false}

      {{:curly, :"}", _}, _index}, _ ->
        {:halt, false}

      {{:identifier, 'alias', _}, 0}, _ ->
        # there is nothing after the alias directive, so we're not
        # inside the context *yet*
        {:halt, false}

      {{:identifier, 'alias', _}, _index}, _ ->
        {:halt, true}

      _, _ ->
        {:cont, false}
    end)
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :import) do
    in_directive?(env, 'import')
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :use) do
    in_directive?(env, 'use')
  end

  @impl Environment
  def in_context?(%__MODULE__{} = env, :require) do
    in_directive?(env, 'require')
  end

  @impl Environment
  def empty?("") do
    true
  end

  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end

  @behaviour Builder

  @impl Builder
  def snippet(%Env{}, snippet_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, snippet_text)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
    |> boost(0)
  end

  @impl Builder
  def plain_text(%Env{}, insert_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, insert_text)
    |> Completion.Item.new()
    |> boost(0)
  end

  @impl Builder
  def text_edit(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    line_number = env.position.line
    range = Range.new(Position.new(line_number, start_char), Position.new(line_number, end_char))
    edits = Document.Changes.new(env.document, Edit.new(text, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Completion.Item.new()
    |> boost(0)
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
    |> boost(0)
  end

  @impl Builder
  def fallback(nil, fallback), do: fallback
  def fallback("", fallback), do: fallback
  def fallback(detail, _), do: detail

  @impl Builder
  def boost(item, local_boost \\ 1, global_boost \\ 0)

  def boost(%Completion.Item{} = item, local_boost, global_boost)
      when local_boost in 0..9 and global_boost in 0..9 do
    global_boost = Integer.to_string(9 - global_boost)
    local_boost = Integer.to_string(9 - local_boost)

    sort_text = "0#{global_boost}#{local_boost}_#{item.label}"
    %Completion.Item{item | sort_text: sort_text}
  end

  # end builder behaviour

  @spec strip_struct_reference(t()) :: {Document.t(), Position.t()}
  def strip_struct_reference(%__MODULE__{} = env) do
    if in_context?(env, :struct_reference) do
      do_strip_struct_reference(env)
    else
      {env.document, env.position}
    end
  end

  @spec prefix_alias_position(Env.t()) :: {integer(), integer()} | nil
  def prefix_alias_position(env) do
    env
    |> cursor_path()
    |> Enum.find_value(fn
      {:%, _, [{:__aliases__, [line: line, column: column], _aliases} | _]} -> {line, column}
      {:%, _, [{:__MODULE__, [line: line, column: column], _} | _]} -> {line, column}
      _ -> nil
    end)
  end

  # private

  defp do_strip_struct_reference(%__MODULE__{} = env) do
    completion_length =
      case Code.Fragment.cursor_context(env.prefix) do
        {:struct, {:dot, {:alias, struct_name}, []}} ->
          # add one because of the trailing period
          length(struct_name) + 1

        {:struct, {:local_or_var, local_name}} ->
          length(local_name)

        {:struct, struct_name} ->
          length(struct_name)

        {:local_or_var, local_name} ->
          length(local_name)
      end

    column = env.position.character
    percent_position = column - (completion_length + 1)

    new_line_start = String.slice(env.line, 0, percent_position - 1)
    new_line_end = String.slice(env.line, percent_position..-1)
    new_line = [new_line_start, new_line_end]
    new_position = Position.new(env.position.line, env.position.character - 1)
    line_to_replace = env.position.line

    new_document =
      env.document.lines
      |> Enum.with_index(1)
      |> Enum.reduce([], fn
        {line(ending: ending), ^line_to_replace}, acc ->
          [acc, new_line, ending]

        {line(text: line_text, ending: ending), _}, acc ->
          [acc, line_text, ending]
      end)
      |> IO.iodata_to_binary()

    {new_document, new_position}
  end

  defp in_directive?(%__MODULE__{} = env, context_name) do
    env
    |> prefix_token_stream()
    |> Enum.reduce_while(false, fn
      {:identifier, ^context_name, _}, _ ->
        {:halt, true}

      {:eol, _, _}, _ ->
        {:halt, false}

      _, _ ->
        {:cont, false}
    end)
  end

  defp cursor_context(%__MODULE__{} = env) do
    with {:ok, line} <- Document.fetch_text_at(env.document, env.position.line) do
      fragment = String.slice(line, 0..(env.zero_based_character - 1))
      {:ok, line, Code.Fragment.cursor_context(fragment)}
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp normalize_token(token) do
    case token do
      :eol ->
        {:eol, '\n', []}

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

      {type, {line, column, nil}, value} when is_list(value) ->
        {normalize_type(type), value, {line, column}}

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

  defp prefix_token_stream(%__MODULE__{} = env) do
    init_function = fn ->
      {env, '', env.position.line}
    end

    next_function = fn
      {env, _, 0} ->
        {:halt, env}

      {env, current_context, line_number} ->
        case find_and_tokenize(env, line_number, current_context) do
          {:ok, tokens, new_context} ->
            prev_line_number = line_number - 1

            tokens =
              if prev_line_number > 0 do
                tokens ++ [:eol]
              else
                tokens
              end

            {tokens, {env, new_context, prev_line_number}}

          :stop ->
            {:halt, env}
        end
    end

    finalize_function = fn _ -> :ok end

    init_function
    |> Stream.resource(next_function, finalize_function)
    |> Stream.map(&normalize_token/1)
  end

  defp find_and_tokenize(%__MODULE__{position: %{line: line_number}} = env, line_number, context) do
    tokenize(env.prefix, line_number, context)
  end

  defp find_and_tokenize(%__MODULE__{} = env, line_number, context) do
    case Document.fetch_text_at(env.document, line_number) do
      {:ok, line_text} ->
        tokenize(line_text, line_number, context)

      :error ->
        :stop
    end
  end

  defp tokenize(line_text, line_number, context) do
    line_charlist = String.to_charlist(line_text)
    current_context = line_charlist ++ context

    case :elixir_tokenizer.tokenize(current_context, line_number, 1, []) do
      {:ok, _, _, _, tokens} ->
        {:ok, Enum.reverse(tokens), ''}

      {:error, {_, _, 'unexpected token: ', _}, _, _, _} ->
        {:ok, [], '\n' ++ current_context}

      {:error, _, _, _, tokens} ->
        {:ok, tokens, ''}
    end
  end

  defp ancestor_is_def?(env) do
    env
    |> cursor_path()
    |> Enum.any?(fn
      {:def, _, _} ->
        true

      {:defp, _, _} ->
        true

      _ ->
        false
    end)
  end

  defp ancestor_is_type?(env) do
    env
    |> cursor_path()
    |> Enum.any?(fn
      {:type, _, _} -> true
      _ -> false
    end)
  end

  defp cursor_path(env) do
    fragment = Document.fragment(env.document, env.position)

    case Code.Fragment.container_cursor_to_quoted(fragment, columns: true) do
      {:ok, quoted} ->
        quoted
        |> Macro.path(&match?({:__cursor__, _, _}, &1))
        |> List.wrap()

      _ ->
        []
    end
  end
end
