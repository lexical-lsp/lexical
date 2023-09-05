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

  require Logger

  @type resolved :: {:module, module()}

  @doc """
  Attempts to resolve the entity at the given position in the document.

  ## Return values

  Returns `{:ok, resolved, range}` if successful and `{:error, error}`
  otherwise. The `range` includes the resolved node and the
  Resolved entities are one of:

    * `{:module, module}`

  """
  @spec resolve(Document.t(), Position.t()) :: {:ok, resolved, Range.t()} | {:error, term()}
  def resolve(%Document{} = document, %Position{} = position) do
    with {:ok, %{context: context, begin: begin_pos, end: end_pos}} <-
           Ast.surround_context(document, position),
         {:ok, resolved, {begin_pos, end_pos}} <-
           resolve(context, {begin_pos, end_pos}, document, position) do
      Logger.info("Resolved entity: #{inspect(resolved)}")
      {:ok, resolved, to_range(begin_pos, end_pos)}
    else
      {:error, :surround_context} -> {:error, :not_found}
      error -> error
    end
  end

  defp resolve({:alias, charlist}, node_range, document, position) do
    resolve_module(charlist, node_range, document, position)
  end

  defp resolve({:alias, {:local_or_var, prefix}, charlist}, node_range, document, position) do
    resolve_module(prefix ++ [?.] ++ charlist, node_range, document, position)
  end

  defp resolve({:local_or_var, ~c"__MODULE__"}, node_range, document, position) do
    resolve_module(~c"__MODULE__", node_range, document, position)
  end

  defp resolve(context, _node_range, _document, _position) do
    unsupported_context(context)
  end

  defp unsupported_context(context) do
    {:error, {:unsupported, context}}
  end

  # Modules on a single line, e.g. "Foo.Bar.Baz"
  defp resolve_module(charlist, {{line, column}, {line, _}}, document, position)
       when is_list(charlist) do
    # Take only the segments at and before the cursor, e.g.
    # Foo|.Bar.Baz -> Foo
    # Foo.|Bar.Baz -> Foo.Bar
    module_string =
      charlist
      |> Enum.with_index(column)
      |> Enum.take_while(fn {char, column} ->
        column < position.character or char != ?.
      end)
      |> Enum.map(&elem(&1, 0))
      |> List.to_string()

    expanded =
      [module_string]
      |> Module.concat()
      |> Ast.expand_aliases(document, position)

    with {:ok, module} <- expanded do
      {:ok, {:module, module}, {{line, column}, {line, column + String.length(module_string)}}}
    end
  end

  # Modules on multiple lines, e.g. "Foo.\n  Bar.\n  Baz"
  # Since we no longer have formatting information at this point, we
  # just return the entire module for now.
  defp resolve_module(charlist, node_range, document, position) do
    module_string = List.to_string(charlist)

    expanded =
      [module_string]
      |> Module.concat()
      |> Ast.expand_aliases(document, position)

    with {:ok, module} <- expanded do
      {:ok, {:module, module}, node_range}
    end
  end

  @doc """
  Returns the source location of the entity at the given position in the document.
  """
  def definition(%Project{} = project, %Document{} = document, %Position{} = position) do
    project
    |> RemoteControl.Api.definition(document, position)
    |> parse_location(document)
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
