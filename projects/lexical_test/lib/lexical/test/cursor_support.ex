defmodule Lexical.Test.CursorSupport do
  @moduledoc """
  Utilities for extracting cursor position in code fragments and documents.
  """

  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Test.PositionSupport

  @default_cursor "|"
  @starting_line 1
  @starting_column 1

  @type cursor_position :: {pos_integer(), pos_integer()}

  @doc """
  Finds a cursor in `text` and returns a tuple of the cursor position and
  the text with the cursor stripped out.

  ## Options

    * `:cursor` - the cursor string to be found. Defaults to
      `#{inspect(@default_cursor)}`.

    * `:as` - one of `:text` (default) or `:document`. If `:document`,
      wraps the text in a `Lexical.Document` using the URI `"file:///file.ex"`.

    * `:document` - the document path or URI. Setting this option implies
      `as: :document`.

  ## Examples

      iex> code = \"""
      ...> defmodule MyModule do
      ...>   alias Foo|
      ...> end
      ...> \"""

      iex> pop_cursor(code)
      {
        %Position{line: 2, column: 12},
        \"""
        defmodule MyModule do
          alias Foo
        end
        \"""
      }

      iex> pop_cursor(code, as: :document)
      {
        %Position{line: 2, column: 12},
        %Document{uri: "file:///file.ex", ...}
      }

      iex> pop_cursor(code, document: "my_doc.ex")
      {
        %Position{line: 2, column: 12},
        %Document{uri: "file:///my_doc.ex", ...}
      }

  """
  @spec pop_cursor(text :: String.t(), [opt]) :: {Position.t(), String.t() | Document.t()}
        when opt: {:cursor, String.t()} | {:as, :text | :document} | {:document, String.t()}
  def pop_cursor(text, opts \\ []) do
    cursor = Keyword.get(opts, :cursor, @default_cursor)
    as_document? = opts[:as] == :document or is_binary(opts[:document])

    {line, column} = cursor_position(text, cursor)
    stripped_text = strip_cursor(text, cursor)

    if as_document? do
      uri = opts |> Keyword.get(:document, "file:///file.ex") |> Document.Path.ensure_uri()
      document = Document.new(uri, stripped_text, 0)
      position = Position.new(document, line, column)
      {position, document}
    else
      position = PositionSupport.position(line, column)
      {position, stripped_text}
    end
  end

  @doc """
  Strips all instances of `cursor` from `text`.
  """
  @spec strip_cursor(text :: String.t(), cursor :: String.t()) :: String.t()
  def strip_cursor(text, cursor \\ @default_cursor) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.reduce([], fn
      # don't strip the pipe in a `|>` operator when using the default cursor
      ["|", ">"], iodata ->
        [iodata, "|"]

      [^cursor, _lookahead], iodata ->
        iodata

      [c, _], iodata ->
        [iodata, c]
    end)
    |> IO.iodata_to_binary()
  end

  defp cursor_position(text, cursor) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, [""])
    |> Enum.reduce_while({@starting_line, @starting_column}, fn
      # don't consider the pipe in a `|>` operator when using the default cursor
      ["|", ">"], {line, column} ->
        {:cont, {line, column + 1}}

      [^cursor, _], position ->
        {:halt, position}

      ["\n", _], {line, _column} ->
        {:cont, {line + 1, @starting_column}}

      _, {line, column} ->
        {:cont, {line, column + 1}}
    end)
  end
end
