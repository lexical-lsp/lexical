defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Variable do
  alias Lexical.Ast
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  @defs [:def, :defmacro, :defp, :defmacrop]
  def extract({def, _, [{_fn_name, _, params}, body]}, %Reducer{} = reducer)
      when def in @defs do
    entries = extract_definitions(params, reducer)

    {:ok, entries, body}
  end

  # Stab operator  x -> body
  def extract({:->, _, [params, body]}, %Reducer{} = reducer) do
    entries = extract_definitions(params, reducer) ++ extract_in_definitions(params, reducer)

    {:ok, entries, List.wrap(body)}
  end

  # Match operator left = right
  def extract({:=, _, [left, right]}, %Reducer{} = reducer) do
    definitions = extract_definitions(left, reducer)
    references = extract_references(right, reducer)
    {:ok, definitions ++ references, nil}
  end

  # Generic variable reference
  def extract({var_name, _, _} = ast, %Reducer{} = reducer) when is_atom(var_name) do
    case extract_reference(ast, reducer, get_current_app(reducer)) do
      %Entry{} = entry -> {:ok, entry}
      _ -> :ignored
    end
  end

  # Pin operator ^pinned_variable
  def extract({:^, _, [reference]}, %Reducer{} = reducer) do
    reference = extract_reference(reference, reducer, get_current_app(reducer))
    {:ok, reference, nil}
  end

  def extract(_ast, _reducer) do
    :ignored
  end

  defp extract_definitions(ast, reducer) do
    current_app = get_current_app(reducer)

    {_ast, entries} =
      Macro.prewalk(ast, [], fn ast, acc ->
        case extract_definition(ast, reducer, current_app) do
          %Entry{} = entry ->
            {ast, [entry | acc]}

          {%Entry{} = entry, ast} ->
            {ast, [entry | acc]}

          _ ->
            {ast, acc}
        end
      end)

    Enum.reverse(entries)
  end

  # the pin operator is always on the left side of a pattern match, but it's
  # not defining a variable, just referencing one.
  defp extract_definition({:^, _, [reference]}, %Reducer{} = reducer, current_app) do
    reference = extract_reference(reference, reducer, current_app)

    {reference, nil}
  end

  defp extract_definition({var_name, _metadata, nil} = ast, reducer, current_app) do
    if used_variable?(var_name) do
      document = reducer.analysis.document
      block = Reducer.current_block(reducer)

      Entry.definition(
        document.path,
        block,
        var_name,
        :variable,
        Ast.Range.fetch!(ast, document),
        current_app
      )
    end
  end

  defp extract_definition(_, _reducer, _current_app), do: nil

  defp extract_references(ast, reducer) do
    current_app = get_current_app(reducer)

    {_ast, entries} =
      Macro.prewalk(ast, [], fn ast, acc ->
        case extract_reference(ast, reducer, current_app) do
          %Entry{} = entry ->
            {ast, [entry | acc]}

          _ ->
            {ast, acc}
        end
      end)

    Enum.reverse(entries)
  end

  defp extract_reference({var_name, _metadata, nil} = ast, reducer, current_app) do
    if used_variable?(var_name) do
      document = reducer.analysis.document
      block = Reducer.current_block(reducer)

      Entry.reference(
        document.path,
        block,
        var_name,
        :variable,
        Ast.Range.fetch!(ast, document),
        current_app
      )
    end
  end

  defp extract_reference(_, _, _), do: nil

  # extracts definitions like e in SomeException ->
  defp extract_in_definitions(ast, %Reducer{} = reducer) do
    current_app = get_current_app(reducer)

    {_ast, entries} =
      Macro.prewalk(ast, [], fn ast, acc ->
        case extract_in_definition(ast, reducer, current_app) do
          %Entry{} = entry ->
            {ast, [entry | acc]}

          _ ->
            {ast, acc}
        end
      end)

    Enum.reverse(entries)
  end

  defp extract_in_definition(
         [[{:in, _, [definition, _right]}], _body],
         %Reducer{} = reducer,
         current_app
       ) do
    extract_definition(definition, reducer, current_app)
  end

  defp extract_in_definition(_ast, %Reducer{}, _current_app), do: nil

  defp get_current_app(%Reducer{} = reducer) do
    with {:ok, module} <- Analyzer.current_module(reducer.analysis, Reducer.position(reducer)) do
      Application.get_application(module)
    end
  end

  defp used_variable?(variable_name) do
    not (variable_name
         |> Atom.to_string()
         |> String.starts_with?("_"))
  end
end
