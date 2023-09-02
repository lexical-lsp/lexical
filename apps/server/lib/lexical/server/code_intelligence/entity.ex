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

  @type resolved :: {:module, module()} | {:struct, module()}

  @doc """
  Attempts to resolve the entity at the given position in the document.

  Returns `{:ok, resolved, range}` if successful, `{:error, error}` otherwise.
  """
  @spec resolve(Document.t(), Position.t()) :: {:ok, resolved, Range.t()} | {:error, term()}
  def resolve(%Document{} = document, %Position{} = position) do
    with {:ok, %{context: context, begin: begin_pos, end: end_pos}} <-
           Ast.surround_context(document, position),
         {:ok, resolved, {begin_pos, end_pos}} <-
           resolve(context, {begin_pos, end_pos}, document, position) do
      {:ok, resolved, to_range(document, begin_pos, end_pos)}
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

  defp resolve({:struct, charlist}, {{start_line, start_col}, end_pos}, document, position) do
    # exclude the leading % from the node range so that it can be
    # resolved like a normal module alias
    node_range = {{start_line, start_col + 1}, end_pos}

    case resolve_module(charlist, node_range, document, position) do
      {:ok, {:module, module}, range} -> {:ok, {:struct, module}, range}
      error -> error
    end
  end

  defp resolve(context, _node_range, _document, _position) do
    unsupported_context(context)
  end

  defp unsupported_context(context) do
    {:error, {:unsupported, context}}
  end

  # Modules on a single line, e.g. "Foo.Bar.Baz"
  defp resolve_module(charlist, {{line, column}, {line, _}}, document, position) do
    module_string = module_before_position(charlist, column, position)

    with {:ok, module} <- expand_aliases(module_string, document, position) do
      end_column = column + String.length(module_string)
      {:ok, {:module, module}, {{line, column}, {line, end_column}}}
    end
  end

  # Modules on multiple lines, e.g. "Foo.\n  Bar.\n  Baz"
  # Since we no longer have formatting information at this point, we
  # just return the entire module for now.
  defp resolve_module(charlist, node_range, document, position) do
    module_string = List.to_string(charlist)

    with {:ok, module} <- expand_aliases(module_string, document, position) do
      {:ok, {:module, module}, node_range}
    end
  end

  # Take only the segments at and before the cursor, e.g.
  # Foo|.Bar.Baz -> Foo
  # Foo.|Bar.Baz -> Foo.Bar
  defp module_before_position(charlist, start_column, position) when is_list(charlist) do
    charlist
    |> List.to_string()
    |> module_before_position(position.character - start_column)
  end

  defp module_before_position(string, index) when is_binary(string) do
    {prefix, suffix} = String.split_at(string, index)

    case String.split(suffix, ".", parts: 2) do
      [before_dot, _after_dot] -> prefix <> before_dot
      [before_dot] -> prefix <> before_dot
    end
  end

  defp expand_aliases(module, document, position) when is_binary(module) do
    [module]
    |> Module.concat()
    |> Ast.expand_aliases(document, position)
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
      range = to_precise_range(document, text, line, column)

      {:ok, Location.new(range, document)}
    else
      _ ->
        {:error, "Could not open source file or fetch line text: #{inspect(file_path)}"}
    end
  end

  defp parse_location(nil, _) do
    {:ok, nil}
  end

  defp to_precise_range(%Document{} = document, text, line, column) do
    case Code.Fragment.surround_context(text, {line, column}) do
      %{begin: start_pos, end: end_pos} ->
        to_range(document, start_pos, end_pos)

      _ ->
        # If the column is 1, but the code doesn't start on the first column, which isn't what we want.
        # The cursor will be placed to the left of the actual definition.
        column = if column == 1, do: Text.count_leading_spaces(text) + 1, else: column
        pos = {line, column}
        to_range(document, pos, pos)
    end
  end

  defp to_range(%Document{} = document, {begin_line, begin_column}, {end_line, end_column}) do
    Range.new(
      Position.new(document, begin_line, begin_column),
      Position.new(document, end_line, end_column)
    )
  end
end
