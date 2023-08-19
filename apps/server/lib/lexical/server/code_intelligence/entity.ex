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
         {:ok, zipper} <- innermost_zipper_at(ast, position),
         {:ok, resolved} <- resolve(Zipper.node(zipper), zipper, document, position) do
      Logger.info("Resolved entity: #{inspect(resolved)}")
      {:ok, resolved}
    else
      error ->
        Logger.info("Resolve failed: #{inspect(error)}")
        error
    end
  end

  defp resolve({:__aliases__, _, aliases} = node, zipper, document, position) do
    with {:ok, %{start: start}} <- fetch_range(node) do
      {aliases_with_columns, _} =
        Enum.map_reduce(aliases, start[:column], fn
          {:__MODULE__, _, nil}, column ->
            {{:__MODULE__, column}, column + 10 + 1}

          alias_name, column ->
            alias_len = alias_name |> Atom.to_string() |> String.length()
            {{alias_name, column}, column + alias_len + 1}
        end)

      at_or_before_position =
        for {name, offset} <- aliases_with_columns,
            offset <= position.character do
          name
        end

      case at_or_before_position do
        [:__MODULE__ | rest] ->
          with {:ok, module_aliases} <- current_module_aliases(zipper) do
            {:ok, {:module, Module.concat(module_aliases ++ rest)}}
          end

        aliases ->
          {:ok, module} = Ast.expand_aliases(document, position, aliases)
          {:ok, {:module, module}}
      end
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

    {_, {innermost, _}} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse_while({nil, false}, fn
        {{_, _, _} = node, _} = zipper, {current, found_line?} ->
          case fetch_range(node) do
            {:ok, range} ->
              same_line? = line == range.start[:line] and line == range.end[:line]
              line_in_range? = line >= range.start[:line] and line <= range.end[:line]
              # sourceror column ranges are inclusive at the start and exclusive at the end
              char_in_range? = char >= range.start[:column] and char < range.end[:column]

              cond do
                same_line? and char_in_range? ->
                  {:cont, zipper, {zipper, true}}

                found_line? or same_line? ->
                  {:skip, zipper, {current, true}}

                line_in_range? ->
                  {:cont, zipper, {zipper, false}}

                true ->
                  {:skip, zipper, {current, found_line?}}
              end

            _ ->
              {:cont, zipper, {current, found_line?}}
          end

        zipper, acc ->
          {:cont, zipper, acc}
      end)

    if innermost do
      {:ok, innermost}
    else
      {:error, :not_found}
    end
  end

  # Corrects aliases issue: https://github.com/doorgan/sourceror/issues/99
  defp fetch_range({:__aliases__, _, [{_, meta, _} | _]} = node) do
    range = Sourceror.get_range(node)
    {:ok, put_in(range.start[:column], meta[:column])}
  end

  # Corrects dot-call issue
  defp fetch_range({:., _, [left, atom]}) when is_atom(atom) do
    with {:ok, range} <- fetch_range(left) do
      # Unhandled edge case: quoted atoms, e.g. Foo."bar-baz"
      len = atom |> Atom.to_string() |> String.length()
      {:ok, update_in(range.end[:column], &(&1 + 1 + len))}
    end
  end

  # There are certain AST nodes that fail on Sourceror.get_range/1, like
  # string interpolation segments, for instance. Instead of causing an
  # error in the server, we just bail out on fetching the range.
  defp fetch_range(node) do
    {:ok, Sourceror.get_range(node)}
  rescue
    _ ->
      Logger.warning("Couldn't get range for node: #{inspect(node)}")
      {:error, :no_range}
  end

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
