defmodule Lexical.RemoteControl.CodeIntelligence.Entity do
  alias Future.Code, as: Code
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl

  require Logger
  require Sourceror.Identifier

  @type resolved ::
          {:module, module()}
          | {:struct, module()}
          | {:call, module(), fun_name :: atom(), arity :: non_neg_integer()}
          | {:type, module(), type_name :: atom(), arity :: non_neg_integer()}
          | {:module_attribute, container_module :: module(), attribut_name :: atom()}
          | {:variable, variable_name :: atom()}

  defguardp is_call(form) when Sourceror.Identifier.is_call(form) and elem(form, 0) != :.

  @doc """
  Attempts to resolve the entity at the given position in the document.

  Returns `{:ok, resolved, range}` if successful, `{:error, error}` otherwise.
  """
  @spec resolve(Analysis.t(), Position.t()) :: {:ok, resolved, Range.t()} | {:error, term()}
  def resolve(%Analysis{} = analysis, %Position{} = position) do
    analysis = Ast.reanalyze_to(analysis, position)

    with {:ok, surround_context} <- Ast.surround_context(analysis, position),
         {:ok, resolved, {begin_pos, end_pos}} <- resolve(surround_context, analysis, position) do
      Logger.info("Resolved entity: #{inspect(resolved)}")
      {:ok, resolved, to_range(analysis.document, begin_pos, end_pos)}
    else
      :error -> {:error, :not_found}
      {:error, :surround_context} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @spec to_range(Document.t(), Code.position(), Code.position()) :: Range.t()
  def to_range(%Document{} = document, {begin_line, begin_column}, {end_line, end_column}) do
    Range.new(
      Position.new(document, begin_line, begin_column),
      Position.new(document, end_line, end_column)
    )
  end

  defp resolve(%{context: context, begin: begin_pos, end: end_pos}, analysis, position) do
    resolve(context, {begin_pos, end_pos}, analysis, position)
  end

  defp resolve({:alias, charlist}, node_range, analysis, position) do
    resolve_alias(charlist, node_range, analysis, position)
  end

  defp resolve({:alias, {:local_or_var, prefix}, charlist}, node_range, analysis, position) do
    resolve_alias(prefix ++ [?.] ++ charlist, node_range, analysis, position)
  end

  defp resolve({:local_or_var, ~c"__MODULE__" = chars}, node_range, analysis, position) do
    resolve_alias(chars, node_range, analysis, position)
  end

  defp resolve({:local_or_var, chars}, node_range, analysis, position) do
    maybe_fun = List.to_atom(chars)

    case Ast.path_at(analysis, position) do
      {:ok, [{^maybe_fun, _, nil} = local, {def, _, [local | _]} | _]}
      when def in [:def, :defp] ->
        # This case handles resolving calls that come from zero-arg definitions in
        # a module, like hovering in `def my_fun| do`
        {:ok, module} = RemoteControl.Analyzer.current_module(analysis, position)
        {:ok, {:call, module, maybe_fun, 0}, node_range}

      {:ok, [{^maybe_fun, _, args} | _]} ->
        # imported functions
        arity =
          case args do
            arg_list when is_list(arg_list) -> length(arg_list)
            _ -> 0
          end

        case fetch_module_for_function(analysis, position, maybe_fun, arity) do
          {:ok, module} -> {:ok, {:call, module, maybe_fun, arity}, node_range}
          _ -> {:ok, {:variable, List.to_atom(chars)}, node_range}
        end

      _ ->
        {:ok, {:variable, List.to_atom(chars)}, node_range}
    end
  end

  defp resolve({:struct, charlist}, {{start_line, start_col}, end_pos}, analysis, position) do
    # exclude the leading % from the node range so that it can be
    # resolved like a normal module alias
    node_range = {{start_line, start_col + 1}, end_pos}

    case resolve_alias(charlist, node_range, analysis, position) do
      {:ok, {struct_or_module, struct}, range} -> {:ok, {struct_or_module, struct}, range}
      :error -> {:error, :not_found}
    end
  end

  defp resolve({:dot, alias_node, fun_chars}, node_range, analysis, position) do
    fun = List.to_atom(fun_chars)

    with {:ok, module} <- expand_alias(alias_node, analysis, position) do
      case Ast.path_at(analysis, position) do
        {:ok, path} ->
          arity = arity_at_position(path, position)
          kind = kind_of_call(path, position)
          {:ok, {kind, module, fun, arity}, node_range}

        _ ->
          {:ok, {:call, module, fun, 0}, node_range}
      end
    end
  end

  defp resolve({:local_call, fun_chars}, node_range, analysis, position) do
    fun = List.to_atom(fun_chars)

    with {:ok, path} <- Ast.path_at(analysis, position),
         arity = arity_at_position(path, position),
         {module, ^fun, ^arity} <-
           RemoteControl.Analyzer.resolve_local_call(analysis, position, fun, arity) do
      {:ok, {:call, module, fun, arity}, node_range}
    else
      _ ->
        {:ok, module} = RemoteControl.Analyzer.current_module(analysis, position)
        {:ok, {:call, module, fun, 0}, node_range}
    end
  end

  defp resolve({:unquoted_atom, _} = context, node_range, analysis, position) do
    case expand_alias(context, analysis, position) do
      {:ok, module} -> {:ok, {:module, module}, node_range}
      _ -> {:error, {:unsupported, context}}
    end
  end

  defp resolve({:module_attribute, attr_name}, node_range, analysis, position) do
    {:ok, current_module} = RemoteControl.Analyzer.current_module(analysis, position)

    {:ok, {:module_attribute, current_module, List.to_atom(attr_name)}, node_range}
  end

  defp resolve(context, _node_range, _analysis, _position) do
    {:error, {:unsupported, context}}
  end

  defp resolve_alias(charlist, node_range, analysis, position) do
    {{_line, start_column}, _} = node_range

    with false <- suffix_contains_module?(charlist, start_column, position),
         {:ok, path} <- Ast.path_at(analysis, position),
         :struct <- kind_of_alias(path) do
      resolve_struct(charlist, node_range, analysis, position)
    else
      _ ->
        resolve_module(charlist, node_range, analysis, position)
    end
  end

  defp resolve_struct(charlist, node_range, analysis, %Position{} = position) do
    with {:ok, struct} <- expand_alias(charlist, analysis, position) do
      {:ok, {:struct, struct}, node_range}
    end
  end

  # Modules on a single line, e.g. "Foo.Bar.Baz"
  defp resolve_module(charlist, {{line, column}, {line, _}}, analysis, %Position{} = position) do
    module_string = module_before_position(charlist, column, position)

    with {:ok, module} <- expand_alias(module_string, analysis, position) do
      end_column = column + String.length(module_string)
      {:ok, {:module, module}, {{line, column}, {line, end_column}}}
    end
  end

  # Modules on multiple lines, e.g. "Foo.\n  Bar.\n  Baz"
  # Since we no longer have formatting information at this point, we
  # just return the entire module for now.
  defp resolve_module(charlist, node_range, analysis, %Position{} = position) do
    with {:ok, module} <- expand_alias(charlist, analysis, position) do
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

  # %TopLevel|.Struct{} -> true
  # %TopLevel.Str|uct{} -> false
  defp suffix_contains_module?(charlist, start_column, %Position{} = position) do
    charlist
    |> List.to_string()
    |> suffix_contains_module?(position.character - start_column)
  end

  defp suffix_contains_module?(string, index) when is_binary(string) do
    {_, suffix} = String.split_at(string, index)

    case String.split(suffix, ".", parts: 2) do
      [_before_dot, after_dot] ->
        uppercase?(after_dot)

      [_before_dot] ->
        false
    end
  end

  defp uppercase?(after_dot) when is_binary(after_dot) do
    first_char = String.at(after_dot, 0)
    String.upcase(first_char) == first_char
  end

  defp expand_alias({:alias, {:local_or_var, prefix}, charlist}, analysis, %Position{} = position) do
    expand_alias(prefix ++ [?.] ++ charlist, analysis, position)
  end

  defp expand_alias({:alias, charlist}, analysis, %Position{} = position) do
    expand_alias(charlist, analysis, position)
  end

  defp expand_alias({:unquoted_atom, maybe_module_charlist}, _analysis, _position) do
    maybe_module = List.to_existing_atom(maybe_module_charlist)

    if function_exported?(maybe_module, :module_info, 1) do
      {:ok, maybe_module}
    else
      :error
    end
  rescue
    ArgumentError ->
      :error
  end

  defp expand_alias(charlist, analysis, %Position{} = position) when is_list(charlist) do
    charlist
    |> List.to_string()
    |> expand_alias(analysis, position)
  end

  defp expand_alias(module, analysis, %Position{} = position) when is_binary(module) do
    [module]
    |> Module.concat()
    |> RemoteControl.Analyzer.expand_alias(analysis, position)
  end

  defp expand_alias(_, _analysis, _position), do: :error

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

  # Calls as part of a capture:
  # &MyModule.some_function/2
  defp arity_at_position(
         [
           # To correctly identify a fun/arity capture, the zero-arg call
           # should be the first argument to a `/` binary op, and that `/`
           # should be the only argument to a `&` unary op.
           {_, _, []} = call,
           {:/, _, [call, {:__block__, _, [arity]}]} = slash,
           {:&, _, [slash]} | _
         ],
         _position
       )
       when is_call(call) and is_integer(arity) do
    arity
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

  # |%Foo{}
  defp kind_of_alias([{:%, _, _}]), do: :struct

  # %|Foo{}
  # %|Foo.Bar{}
  # %__MODULE__.|Foo{}
  defp kind_of_alias([{:__aliases__, _, _}, {:%, _, _} | _]), do: :struct

  # %|__MODULE__{}
  defp kind_of_alias([{:__MODULE__, _, nil}, {:%, _, _} | _]), do: :struct

  # %Foo|{}
  defp kind_of_alias([{:%{}, _, _}, {:%, _, _} | _]), do: :struct

  # %|__MODULE__.Foo{}
  defp kind_of_alias([head_of_aliases, {:__aliases__, _, [head_of_aliases | _]}, {:%, _, _} | _]) do
    :struct
  end

  # Catch-all:
  defp kind_of_alias(_), do: :module

  defp fetch_module_for_function(analysis, position, function_name, arity) do
    with :error <- fetch_module_for_local_function(analysis, position, function_name, arity) do
      fetch_module_for_imported_function(analysis, position, function_name, arity)
    end
  end

  defp fetch_module_for_imported_function(analysis, position, function_name, arity) do
    analysis
    |> RemoteControl.Analyzer.imports_at(position)
    |> Enum.find_value({:error, :not_found}, fn
      {imported_module, ^function_name, ^arity} ->
        {:ok, imported_module}

      _ ->
        false
    end)
  end

  defp fetch_module_for_local_function(analysis, position, function_name, arity) do
    with {:ok, current_module} <- RemoteControl.Analyzer.current_module(analysis, position),
         true <- function_exported?(current_module, function_name, arity) do
      {:ok, current_module}
    else
      _ -> :error
    end
  end
end
