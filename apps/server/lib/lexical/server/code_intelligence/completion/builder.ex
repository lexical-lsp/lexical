defmodule Lexical.Server.CodeIntelligence.Completion.Builder do
  @moduledoc """
  Default completion builder.

  For broader compatibility and control, this builder always creates text
  edits, as opposed to simple text insertions. This allows the replacement
  range to be adjusted based on the kind of completion.

  When completions are built using `plain_text/3` or `snippet/3`, the
  replacement range will be determined by the preceding token.
  """

  alias Future.Code, as: Code
  alias Lexical.Ast.Env
  alias Lexical.Completion.Builder
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.Markup.Content

  import Document.Line

  @behaviour Builder

  @impl Builder
  def snippet(%Env{} = env, text, options \\ []) do
    range = prefix_range(env)
    text_edit_snippet(env, text, range, options)
  end

  @impl Builder
  def plain_text(%Env{} = env, text, options \\ []) do
    range = prefix_range(env)
    text_edit(env, text, range, options)
  end

  @impl Builder
  def text_edit(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    line_number = env.position.line

    range =
      Range.new(
        Position.new(env.document, line_number, start_char),
        Position.new(env.document, line_number, end_char)
      )

    edits = Document.Changes.new(env.document, Edit.new(text, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Completion.Item.new()
    |> markdown_docs()
    |> boost(0)
  end

  @impl Builder
  def text_edit_snippet(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    snippet = String.trim_trailing(text, "\n")
    line_number = env.position.line

    range =
      Range.new(
        Position.new(env.document, line_number, start_char),
        Position.new(env.document, line_number, end_char)
      )

    edits = Document.Changes.new(env.document, Edit.new(snippet, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
    |> markdown_docs()
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

    stripped_sort_text =
      item.sort_text
      |> fallback(item.label)
      |> strip_boost()

    sort_text = "0#{global_boost}#{local_boost}_#{stripped_sort_text}"
    %Completion.Item{item | sort_text: sort_text}
  end

  # HACK: This fixes ElixirSense struct completions for certain cases.
  # We should try removing when we update or remove ElixirSense.
  @spec strip_struct_operator_for_elixir_sense(Env.t()) ::
          {Document.t() | String.t(), Position.t()}
  def strip_struct_operator_for_elixir_sense(%Env{} = env) do
    do_strip_struct_operator(env)
  end

  # private

  defp prefix_range(%Env{} = env) do
    end_char = env.position.character
    start_char = end_char - prefix_length(env)
    {start_char, end_char}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp prefix_length(%Env{} = env) do
    case Code.Fragment.cursor_context(env.prefix) do
      {:alias, alias_charlist} ->
        alias_charlist
        |> :string.split(~c".", :all)
        |> List.last()
        |> length()

      {:dot, _inside_dot, charlist} ->
        length(charlist)

      {:dot_arity, _inside_dot, charlist} ->
        length(charlist)

      {:dot_call, _inside_dot, _charlist} ->
        0

      :expr ->
        String.length(env.prefix)

      {:local_or_var, local} ->
        length(local)

      {:local_arity, local} ->
        length(local)

      {:local_call, call} ->
        length(call)

      {:module_attribute, attr} ->
        length(attr)

      {:operator, operator} ->
        length(operator)

      {:operator_arity, _} ->
        0

      {:operator_call, _} ->
        0

      {:sigil, sigil} ->
        # The sigil charlist doesn't include the leading `~`
        length(sigil) + 1

      {:struct, struct} ->
        length(struct)

      :none ->
        0

      {:unquoted_atom, atom} ->
        # add one to include the leading colon, which isn't included
        # in the atom charlist
        length(atom) + 1
    end
  end

  defp do_strip_struct_operator(env) do
    with true <- Env.in_context?(env, :struct_reference),
         {:ok, completion_length} <- fetch_struct_completion_length(env) do
      column = env.position.character
      percent_position = column - (completion_length + 1)

      new_line_start = String.slice(env.line, 0, percent_position - 1)
      new_line_end = String.slice(env.line, percent_position..-1//1)
      new_line = [new_line_start, new_line_end]
      new_position = Position.new(env.document, env.position.line, env.position.character - 1)
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
    else
      _ ->
        {env.document, env.position}
    end
  end

  defp fetch_struct_completion_length(env) do
    case Code.Fragment.cursor_context(env.prefix) do
      {:struct, {:dot, {:alias, struct_name}, []}} ->
        # add one because of the trailing period
        {:ok, length(struct_name) + 1}

      {:struct, {:local_or_var, local_name}} ->
        {:ok, length(local_name)}

      {:struct, struct_name} ->
        {:ok, length(struct_name)}

      {:local_or_var, local_name} ->
        {:ok, length(local_name)}
    end
  end

  @boost_re ~r/^[0-9_]+/
  defp strip_boost(sort_text) do
    String.replace(sort_text, @boost_re, "")
  end

  defp markdown_docs(%Completion.Item{} = item) do
    case item.documentation do
      doc when is_binary(doc) ->
        %{item | documentation: %Content{kind: :markdown, value: doc}}

      _ ->
        item
    end
  end
end
