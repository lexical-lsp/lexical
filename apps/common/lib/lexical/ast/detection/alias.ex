defmodule Lexical.Ast.Detection.Alias do
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  @behaviour Detection
  @doc """
  Recognizes an alias at the current position

  Aliases are complicated, especially if we're trying to find out if we're in
  them from the current cursor position moving backwards.
  I'll try to describe the state machine below.
  First off, if we're outside of a } on the current line, we cannot be in an alias, so that
  halts with false.
  Similarly an alias on the current line is also simple, we just backtrack until we see the alias identifier.
  However, if we're on the current line, and see an EOL, we set that as our accumulator, then we get
  to the previous line, we see if it ends in a comma. If not, we can't be in an alias. If it does, we keep
  backtracking until we hit the alias keyword.
  So basically, if we hit an EOL, and the previous token isn't an open curly or a comma, we stop, otherwise
  we backtrack until we hit the alias keyword
  """
  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    document
    |> Tokens.prefix_stream(position)
    |> Stream.with_index()
    |> Enum.to_list()
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

      {{:identifier, ~c"alias", _}, 0}, _ ->
        # there is nothing after the alias directive, so we're not
        # inside the context *yet*

        {:halt, false}

      {{:identifier, ~c"alias", _}, _index}, _ ->
        {:halt, true}

      _, _ ->
        {:cont, false}
    end)
  end
end
