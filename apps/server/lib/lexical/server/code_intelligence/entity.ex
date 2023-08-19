defmodule Lexical.Server.CodeIntelligence.Entity do
  alias Future.Code, as: Code
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.Text
  alias Sourceror.Zipper

  require Logger

  @type resolved :: {:module, module()}

  @doc """
  Attempts to resolve the entity at the given position in the document.

  ## Return values

  Returns `{:ok, resolved}` if successful and `{:error, error}` otherwise.
  Resolved entities are one of:

    * `{:module, module}`

  """
  @spec resolve(Document.t(), Position.t()) :: {:ok, resolved} | {:error, term()}
  def resolve(%Document{} = document, %Position{} = position) do
    with {:ok, ast} <- Ast.from(document),
         {:ok, zipper} <- innermost_zipper_at(ast, position) do
      resolve(Zipper.node(zipper), zipper, document, position)
    end
  end

  defp resolve({:__aliases__, _, aliases} = node, zipper, document, position) do
    %{start: start} = get_range(node)

    {with_offsets, _} =
      Enum.map_reduce(aliases, start[:column], fn
        {:__MODULE__, _, nil}, offset ->
          {{:__MODULE__, offset}, offset + 10}

        name, offset ->
          name_len = name |> Atom.to_string() |> String.length()
          {{name, offset}, offset + name_len}
      end)

    before_position =
      with_offsets
      |> Enum.take_while(fn {_name, offset} ->
        offset <= position.character
      end)
      |> Enum.map(&elem(&1, 0))

    case before_position do
      [:__MODULE__ | rest] ->
        with {:ok, module_aliases} <- current_module_aliases(zipper) do
          {:ok, {:module, Module.concat(module_aliases ++ rest)}}
        end

      aliases ->
        {:ok, module} = Ast.expand_aliases(document, position, aliases)
        {:ok, {:module, module}}
    end
  end

  defp resolve({:__MODULE__, _, nil}, zipper, _document, _position) do
    with {:ok, module_aliases} <- current_module_aliases(zipper) do
      {:ok, {:module, Module.concat(module_aliases)}}
    end
  end

  defp resolve(node, _zipper, _document, _position) do
    {:error, {:unsupported, node}}
  end

  defp current_module_aliases(nil), do: {:error, :missing_defmodule}

  defp current_module_aliases(zipper) do
    case Zipper.node(zipper) do
      {:defmodule, _, [{:__aliases__, _, aliases} | _]} -> {:ok, aliases}
      _ -> zipper |> Zipper.up() |> current_module_aliases()
    end
  end

  defp innermost_zipper_at(ast, position) do
    %{line: line, character: char} = position

    {_, innermost} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse_while(nil, fn
        {{_, _, _} = node, _} = zipper, current ->
          range = get_range(node)

          same_line? = line == range.start[:line] and line == range.end[:line]
          line_in_range? = line >= range.start[:line] and line <= range.end[:line]
          char_in_range? = char >= range.start[:column] and char <= range.end[:column]

          if (same_line? and char_in_range?) or (not same_line? and line_in_range?) do
            {:cont, zipper, zipper}
          else
            {:skip, zipper, current}
          end

        zipper, current ->
          {:cont, zipper, current}
      end)

    case innermost do
      nil -> {:error, :not_found}
      zipper -> {:ok, zipper}
    end
  end

  # corrects what appears to be a bug in Elixir's column count when dealing
  # with non-simple-atom aliases, like __MODULE__, where the column is
  # reported after the first token instead of at the beginning of it.
  #
  # Code.string_to_quoted!("Foo.Bar", columns: true)
  # => {:__aliases__, [line: 1, column: 1], [:Foo, :Bar]}
  #
  # Code.string_to_quoted!("__MODULE__.Bar", columns: true)
  # => {:__aliases__, [line: 1, column: 11], [{:__MODULE__, [line: 1, column: 1], nil}, :Bar]}
  #
  # Code.string_to_quoted!("@foo.Bar", columns: true)
  # => {:__aliases__, [line: 1, column: 5],
  #     [{:@, [line: 1, column: 1], [{:foo, [line: 1, column: 2], nil}]}, :Bar]}
  #
  defp get_range({:__aliases__, _, [{_, meta, _} | _]} = node) do
    range = Sourceror.get_range(node)
    put_in(range.start[:column], meta[:column])
  end

  defp get_range(node), do: Sourceror.get_range(node)

  @doc """
  Returns the source location of the entity at the given position in the document.
  """
  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    maybe_location = RemoteControl.Api.definition(project, document, position)
    parse_location(maybe_location, document)
  end

  defp parse_location(%ElixirSense.Location{} = location, document) do
    %{file: file, line: line, column: column} = location
    file_path = file || document.path
    uri = Document.Path.ensure_uri(file_path)

    with {:ok, document} <- Document.Store.open_temporary(uri),
         {:ok, text} <- Document.fetch_text_at(document, line) do
      range = to_precise_range(text, line, column)

      {:ok, Location.new(range, document)}
    else
      _ ->
        {:error, "Could not open source file or fetch line text: #{inspect(file_path)}"}
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp to_precise_range(text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        to_range(start_pos, end_pos)

      _ ->
        # If the column is 1, but the code doesn't start on the first column, which isn't what we want.
        # The cursor will be placed to the left of the actual definition.
        column = if column == 1, do: Text.count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        to_range(pos, pos)
    end
  end

  defp to_range({begin_line, begin_column}, {end_line, end_column}) do
    Range.new(
      Position.new(begin_line, begin_column),
      Position.new(end_line, end_column)
    )
  end
end
