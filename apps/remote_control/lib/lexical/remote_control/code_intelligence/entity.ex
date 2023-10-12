defmodule Lexical.RemoteControl.CodeIntelligence.Entity do
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
  require Sourceror.Identifier

  @type resolved ::
          {:module, module()}
          | {:struct, module()}
          | {:call, module(), fun_name :: atom(), arity :: non_neg_integer()}
          | {:type, module(), type_name :: atom(), arity :: non_neg_integer()}

  defguardp is_call(form) when Sourceror.Identifier.is_call(form) and elem(form, 0) != :.

  @doc """
  Attempts to resolve the entity at the given position in the document.

  Returns `{:ok, resolved, range}` if successful, `{:error, error}` otherwise.
  """
  @spec resolve(Document.t(), Position.t()) :: {:ok, resolved, Range.t()} | {:error, term()}
  def resolve(%Document{} = document, %Position{} = position) do
    with {:ok, surround_context} <- Ast.surround_context(document, position),
         {:ok, resolved, {begin_pos, end_pos}} <- resolve(surround_context, document, position) do
      Logger.info("Resolved entity: #{inspect(resolved)}")
      {:ok, resolved, to_range(document, begin_pos, end_pos)}
    else
      {:error, :surround_context} -> {:error, :not_found}
      error -> error
    end
  end

  defp resolve(%{context: context, begin: begin_pos, end: end_pos}, document, position) do
    resolve(context, {begin_pos, end_pos}, document, position)
  end

  defp resolve({:alias, charlist}, node_range, document, position) do
    resolve_alias(charlist, node_range, document, position)
  end

  defp resolve({:alias, {:local_or_var, prefix}, charlist}, node_range, document, position) do
    resolve_alias(prefix ++ [?.] ++ charlist, node_range, document, position)
  end

  defp resolve({:local_or_var, ~c"__MODULE__" = chars}, node_range, document, position) do
    resolve_alias(chars, node_range, document, position)
  end

  defp resolve({:struct, charlist}, {{start_line, start_col}, end_pos}, document, position) do
    # exclude the leading % from the node range so that it can be
    # resolved like a normal module alias
    node_range = {{start_line, start_col + 1}, end_pos}

    case resolve_alias(charlist, node_range, document, position) do
      {:ok, {_, struct}, range} -> {:ok, {:struct, struct}, range}
      :error -> {:error, :not_found}
    end
  end

  defp resolve({:dot, alias_node, fun_chars}, node_range, document, position) do
    fun = List.to_atom(fun_chars)

    with {:ok, module} <- expand_alias(alias_node, document, position) do
      case Ast.path_at(document, position) do
        {:ok, path} ->
          arity = arity_at_position(path, position)
          kind = kind_of_call(path, position)
          {:ok, {kind, module, fun, arity}, node_range}

        _ ->
          {:ok, {:call, module, fun, 0}, node_range}
      end
    end
  end

  defp resolve(context, _node_range, _document, _position) do
    {:error, {:unsupported, context}}
  end

  defp resolve_alias(charlist, node_range, document, position) do
    with {:ok, path} <- Ast.path_at(document, position),
         :struct <- kind_of_alias(path) do
      resolve_struct(charlist, node_range, document, position)
    else
      _ -> resolve_module(charlist, node_range, document, position)
    end
  end

  defp resolve_struct(charlist, node_range, document, %Position{} = position) do
    with {:ok, struct} <- expand_alias(charlist, document, position) do
      {:ok, {:struct, struct}, node_range}
    end
  end

  # Modules on a single line, e.g. "Foo.Bar.Baz"
  defp resolve_module(charlist, {{line, column}, {line, _}}, document, %Position{} = position) do
    module_string = module_before_position(charlist, column, position)

    with {:ok, module} <- expand_alias(module_string, document, position) do
      end_column = column + String.length(module_string)
      {:ok, {:module, module}, {{line, column}, {line, end_column}}}
    end
  end

  # Modules on multiple lines, e.g. "Foo.\n  Bar.\n  Baz"
  # Since we no longer have formatting information at this point, we
  # just return the entire module for now.
  defp resolve_module(charlist, node_range, document, %Position{} = position) do
    with {:ok, module} <- expand_alias(charlist, document, position) do
      {:ok, {:module, module}, node_range}
    end
  end

  # Take only the segments at and before the cursor, e.g.
  # Foo|.Bar.Baz -> Foo
  # Foo.|Bar.Baz -> Foo.Bar
  defp module_before_position(charlist, start_column, %Position{} = position)
       when is_list(charlist) do
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

  defp expand_alias({:alias, {:local_or_var, prefix}, charlist}, document, %Position{} = position) do
    expand_alias(prefix ++ [?.] ++ charlist, document, position)
  end

  defp expand_alias({:alias, charlist}, document, %Position{} = position) do
    expand_alias(charlist, document, position)
  end

  defp expand_alias(charlist, document, %Position{} = position) when is_list(charlist) do
    charlist
    |> List.to_string()
    |> expand_alias(document, position)
  end

  defp expand_alias(module, document, %Position{} = position) when is_binary(module) do
    [module]
    |> Module.concat()
    |> Ast.expand_aliases(document, position)
  end

  defp expand_alias(_, _document, _position), do: :error

  # Pipes:
  defp arity_at_position([{:|>, _, _} = pipe | _], %Position{} = position) do
    {_call, _, args} =
      pipe
      |> Macro.unpipe()
      |> Enum.find_value(fn {ast, _arg_position} ->
        if Ast.contains_position?(ast, position) do
          ast
        end
      end)

    length(args) + 1
  end

  # Calls inside of a pipe:
  # |> MyModule.some_function(1, 2)
  defp arity_at_position([{_, _, args} = call, {:|>, _, _} | _], _position) when is_call(call) do
    length(args) + 1
  end

  # Calls not inside of a pipe:
  # MyModule.some_function(1, 2)
  # some_function.(1, 2)
  defp arity_at_position([{_, _, args} = call | _], _position) when is_call(call) do
    length(args)
  end

  defp arity_at_position([_non_call | rest], %Position{} = position) do
    arity_at_position(rest, position)
  end

  defp arity_at_position([], _position), do: 0

  # Walk up the path to see whether we're in the right-hand argument of
  # a `::` type operator, which would make the kind a `:type`, not a call.
  # Calls that occur on the right of a `::` type operator have kind `:type`
  defp kind_of_call([{:"::", _, [_, right_arg]} | rest], %Position{} = position) do
    if Ast.contains_position?(right_arg, position) do
      :type
    else
      kind_of_call(rest, position)
    end
  end

  defp kind_of_call([_ | rest], %Position{} = position) do
    kind_of_call(rest, position)
  end

  defp kind_of_call([], _position), do: :call

  # There is a fixed set of situations where an alias is being used as
  # a `:struct`, otherwise resolve as a `:module`.
  defp kind_of_alias(path)

  # %|Foo{}
  # %|Foo.Bar{}
  # %__MODULE__.|Foo{}
  defp kind_of_alias([{:__aliases__, _, _}, {:%, _, _} | _]), do: :struct

  # %|__MODULE__{}
  defp kind_of_alias([{:__MODULE__, _, nil}, {:%, _, _} | _]), do: :struct

  # %|__MODULE__.Foo{}
  defp kind_of_alias([head_of_aliases, {:__aliases__, _, [head_of_aliases | _]}, {:%, _, _} | _]) do
    :struct
  end

  # Catch-all:
  defp kind_of_alias(_), do: :module

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
