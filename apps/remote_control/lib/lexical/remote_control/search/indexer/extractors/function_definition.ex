defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionDefinition do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer
  alias Lexical.RemoteControl.Search.Subject

  @function_definitions [:def, :defp]

  def extract({definition, _, [{fn_name, _, args} = def_ast, body]} = ast, %Reducer{} = reducer)
      when is_atom(fn_name) and definition in @function_definitions do
    with {:ok, detail_range} <- Ast.Range.fetch(def_ast, reducer.analysis.document),
         {:ok, module} <- Analyzer.current_module(reducer.analysis, detail_range.start),
         {fun_name, arity} when is_atom(fun_name) <- fun_name_and_arity(def_ast) do
      entry =
        Entry.block_definition(
          reducer.analysis.document.path,
          Reducer.current_block(reducer),
          Subject.mfa(module, fun_name, arity),
          type(definition),
          block_range(reducer.analysis, ast),
          detail_range,
          Application.get_application(module)
        )

      {:ok, entry, [args, body]}
    else
      _ ->
        :ignored
    end
  end

  def extract(_ast, _reducer) do
    :ignored
  end

  defp type(:def), do: {:function, :public}
  defp type(:defp), do: {:function, :private}

  defp fun_name_and_arity({:when, _, [{fun_name, _, fun_args} | _]}) do
    # a function with guards
    {fun_name, arity(fun_args)}
  end

  defp fun_name_and_arity({fun_name, _, fun_args}) do
    {fun_name, arity(fun_args)}
  end

  defp arity(nil), do: 0
  defp arity(args) when is_list(args), do: length(args)

  defp block_range(%Analysis{} = analysis, def_ast) do
    case Ast.Range.fetch(def_ast, analysis.document) do
      {:ok, range} -> range
      _ -> nil
    end
  end
end
