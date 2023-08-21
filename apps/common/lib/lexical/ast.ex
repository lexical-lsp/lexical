defmodule Lexical.Ast do
  alias Future.Code, as: Code
  alias Lexical.Ast.Aliases
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Sourceror.Zipper

  require Logger
  require Sourceror

  @type t :: any()

  def from(%Document{} = document) do
    document
    |> Document.to_string()
    |> from()
  end

  def from(s) when is_binary(s) do
    parse(s)
  end

  defp parse(s) when is_binary(s) do
    case Sourceror.string_to_quoted(s, token_metadata: true, columns: true) do
      {:ok, code, _comments} ->
        {:ok, code}

      error ->
        error
    end
  end

  @doc """
  Returns the path to the cursor in the given document and position.
  """
  def cursor_path(%Document{} = doc, {line, character}) do
    cursor_path(doc, Position.new(line, character))
  end

  def cursor_path(%Document{} = document, %Position{} = position) do
    fragment = Document.fragment(document, position)

    case Code.Fragment.container_cursor_to_quoted(fragment, columns: true) do
      {:ok, quoted} ->
        quoted
        |> Future.Macro.path(&match?({:__cursor__, _, _}, &1))
        |> List.wrap()

      _ ->
        []
    end
  end

  def zipper_at(%Document{} = document, %Document.Position{} = position) do
    with {:ok, ast} <- from(document) do
      zipper =
        ast
        |> Zipper.zip()
        |> Zipper.find(fn node ->
          within_range?(node, position)
        end)

      {:ok, zipper}
    end
  end

  def traverse_line(%Document{} = document, line_number, fun) when is_integer(line_number) do
    range = one_line_range(line_number)
    traverse_in(document, range, fun)
  end

  def traverse_line(%Document{} = document, line_number, acc, fun) when is_integer(line_number) do
    range = one_line_range(line_number)
    traverse_in(document, range, acc, fun)
  end

  def patches_to_edits(patches) do
    maybe_edits =
      Enum.reduce_while(patches, [], fn patch, edits ->
        case patch_to_edit(patch) do
          {:ok, edit} -> {:cont, [edit | edits]}
          error -> {:halt, error}
        end
      end)

    case maybe_edits do
      edits when is_list(edits) -> {:ok, Enum.reverse(edits)}
      error -> error
    end
  end

  def patch_to_edit(%{change: change, range: %{start: start_pos, end: end_pos}}) do
    with {:ok, range} <- patch_to_range(start_pos, end_pos) do
      {:ok, Edit.new(change, range)}
    end
  end

  @doc """
  Expands the aliases in the given `document`, `postion` and `module_aliases`.

  When we refer to a module, it's usually a short name,
  so it's probably aliased or in a nested module,
  so we need to find the real full name of the module at the cursor position.

  For example, if we have:

    ```elixir
    defmodule Project do
      defmodule Issue do
        defstruct [:message]
      end

      def message(%Issue{|} = issue) do # cursor marked as `|`
      end
    end
    ```

  Then the the expanded module is `Project.Issue`.

  Another example:

    ```elixir
    defmodule Project do
      defmodule Issue do
        defstruct [:message]
      end
    end

    defmodule MyModule do
      alias Project, as: MyProject

      def message(%MyProject.Issue{|} = issue) do
      end
    end
    ```

  Then the the expanded module is still `Project.Issue`.

  And sometimes we can't find the full name by the `Aliases.at/2` function,
  then we just return the `Module.concat(module_aliases)` as it is.
  """
  @type short_alias :: atom()
  @type module_aliases :: [short_alias]

  @spec expand_aliases(
          document :: Document.t(),
          position :: Position.t(),
          module_aliases :: module_aliases()
        ) :: {:ok, module()} | :error
  def expand_aliases(%Document{} = document, %Position{} = position, module_aliases)
      when is_list(module_aliases) do
    [first | rest] = module_aliases

    with {:ok, aliases_mapping} <- Aliases.at(document, position),
         {:ok, from} <- Map.fetch(aliases_mapping, first) do
      {:ok, Module.concat([from | rest])}
    else
      _ ->
        {:ok, Module.concat(module_aliases)}
    end
  end

  def expand_aliases(_, _, nil) do
    Logger.warning("Aliases are nil, can't expand them")
    :error
  end

  defp patch_to_range(start_pos, end_pos) do
    with {:ok, start_pos} <- patch_to_position(start_pos),
         {:ok, end_pos} <- patch_to_position(end_pos) do
      {:ok, Document.Range.new(start_pos, end_pos)}
    end
  end

  defp patch_to_position(patch_keyword) do
    with {:ok, line} <- Keyword.fetch(patch_keyword, :line),
         {:ok, column} <- Keyword.fetch(patch_keyword, :column) do
      {:ok, Document.Position.new(line, column)}
    end
  end

  # in the future, I'd like to expose functions that only traverse a section of the document,
  # but presently, traverse only follows a subtree, so it won't work for our purposes
  defp traverse_in(%Document{} = document, %Document.Range{} = range, fun) do
    ignore_acc = fn node, acc ->
      {fun.(node), acc}
    end

    case traverse_in(document, range, [], ignore_acc) do
      {:ok, zipper, _} ->
        {:ok, zipper}

      error ->
        error
    end
  end

  defp traverse_in(%Document{} = document, %Document.Range{} = range, acc, fun) do
    with {:ok, zipper} <- zipper_at(document, range.start) do
      {zipper, {_position, acc}} =
        Zipper.traverse_while(zipper, {{0, 0}, acc}, fn
          {node, _} = zipper, {last_position, acc} ->
            current_position = node_position(node, last_position)

            if within_range?(current_position, range) do
              {zipper, new_acc} = fun.(zipper, acc)

              {:cont, zipper, {current_position, new_acc}}
            else
              {:skip, zipper, {current_position, acc}}
            end
        end)

      {:ok, zipper, acc}
    end
  end

  defp within_range?({current_line, current_column}, %Document.Range{} = range) do
    start_pos = %Document.Position{} = range.start
    end_pos = %Document.Position{} = range.end

    cond do
      current_line == start_pos.line ->
        current_column >= start_pos.character

      current_line == end_pos.line ->
        current_column <= end_pos.character

      true ->
        current_line >= start_pos.line and current_line <= end_pos.line
    end
  end

  defp within_range?(node, %Document.Position{} = position) do
    line = get_line(node, 0)
    column = get_column(node, 0)

    line >= position.line and column >= position.character
  end

  defp one_line_range(line_number) do
    start_pos = Document.Position.new(line_number, 1)
    end_pos = Document.Position.new(line_number + 1, 0)
    Document.Range.new(start_pos, end_pos)
  end

  defp node_position(node, {line, column}) do
    {get_line(node, line), get_column(node, column)}
  end

  defp get_line([{:do, node}], default) do
    get_line(node, default)
  end

  defp get_line({:do, node}, default) do
    get_line(node, default)
  end

  defp get_line(node, default) when is_tuple(node) and tuple_size(node) == 3 do
    Sourceror.get_line(node, default)
  end

  defp get_line(_, default) do
    default
  end

  defp get_column([do: node], default) do
    get_column(node, default)
  end

  defp get_column({:do, node}, default) do
    get_column(node, default)
  end

  defp get_column(node, default) when is_tuple(node) and tuple_size(node) == 3 do
    Sourceror.get_column(node, default)
  end

  defp get_column(_, default) do
    default
  end
end
