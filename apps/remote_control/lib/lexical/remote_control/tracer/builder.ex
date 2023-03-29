defmodule Lexical.Tracer.Builder do
  require Logger

  def build_module_info(module, file, line) do
    with {:ok, text} <- File.read(file) do
      do_build_module_info(module, file, line, text)
    else
      _ ->
        Logger.warn("can't read file #{file}")
        nil
    end
  end

  defp do_build_module_info(module, file, line, text) do
    defs =
      for {name, arity} <- Module.definitions_in(module) do
        def_info = apply(Module, :get_definition, [module, {name, arity}])
        {{name, arity}, build_def_info(def_info)}
      end

    attributes =
      for name <- apply(Module, :attributes_in, [module]) do
        {name, Module.get_attribute(module, name)}
      end

    %{
      file: file,
      defs: fill_range(text, defs),
      attributes: attributes,
      range: find_module_range(text, line),
      line: line
    }
  end

  def build_def_info({:v1, def_kind, meta_1, clauses}) do
    clauses =
      for {meta_2, arguments, guards, _body} <- clauses do
        %{
          arguments: arguments,
          guards: guards,
          meta: meta_2
        }
      end

    %{
      kind: def_kind,
      clauses: clauses,
      meta: meta_1,
      range: nil
    }
  end

  defp find_module_range(text, line) do
    # Fill the range of the module name.
    ast = Code.string_to_quoted!(text, columns: true)
    {_ast, acc} = Macro.prewalk(ast, %{line: line}, &put_module_range/2)
    Map.get(acc, :range)
  end


  defp fill_range(text, defs) do
    # Fill the range of each def name in the module.
    defs_map =
      for {{name, _arity}, %{kind: kind, meta: [line: line]}} = infos <- defs,
          into: %{} do
        # we use kind, name and line to distinguish between different node
        {{kind, name, line}, infos}
      end

    ast = Code.string_to_quoted!(text, columns: true)
    {_ast, new_defs_map} = Macro.prewalk(ast, defs_map, &put_def_range/2)
    new_defs_map |> Map.values() |> Enum.sort_by(&elem(&1, 1).meta[:line])
  end

  @kind [:def, :defp, :defmacro, :defmacrop]
  defp put_def_range(
         {def_kind, _, [{def_name, [line: line, column: column], _} | _]} = node,
         acc
       )
       when def_kind in @kind do
    result = Map.get(acc, {def_kind, def_name, line})

    case result do
      {fun, info} ->
        info = %{info | range: to_range(line, column, def_name)}
        {node, %{acc | {def_kind, def_name, line} => {fun, info}}}

      _ ->
        {node, acc}
    end
  end

  defp put_def_range(node, acc) do
    {node, acc}
  end

  defp put_module_range(
         {:defmodule, _, [{:__aliases__, [line: line, column: column], module_path} | _]} = node,
         %{line: line} = acc
       ) do
    range = to_range(line, column, Enum.join(module_path, "."))
    {node, Map.put(acc, :range, range)}
  end

  defp put_module_range(node, acc) do
    {node, acc}
  end

  defp to_range(line, column, name) when is_atom(name) do
    name_length = Atom.to_string(name)
    to_range(line, column, name_length)
  end

  defp to_range(line, column, name) do
    name_length = String.length(name)
    # TODO: to Sourcefile.Range
    %{
      start: %{line: line, character: column},
      end: %{line: line, character: column + name_length}
    }
  end
end
