defmodule Lexical.Server.CodeIntelligence.Completion.Builder do
  alias Future.Code, as: Code
  alias Lexical.Ast.Env
  alias Lexical.Completion.Builder
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Protocol.Types.Completion

  import Document.Line

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

    range =
      Range.new(
        Position.new(env.document, line_number, start_char),
        Position.new(env.document, line_number, end_char)
      )

    edits = Document.Changes.new(env.document, Edit.new(text, range))

    options
    |> Keyword.put(:text_edit, edits)
    |> Completion.Item.new()
    |> boost(0)
  end

  @impl Builder
  def text_edit_snippet(%Env{} = env, text, {start_char, end_char}, options \\ []) do
    line_number = env.position.line

    range =
      Range.new(
        Position.new(env.document, line_number, start_char),
        Position.new(env.document, line_number, end_char)
      )

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

  @spec strip_struct_reference(Env.t()) :: {Document.t(), Position.t()}
  def strip_struct_reference(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      do_strip_struct_reference(env)
    else
      {env.document, env.position}
    end
  end

  # private

  defp do_strip_struct_reference(env) do
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
  end
end
