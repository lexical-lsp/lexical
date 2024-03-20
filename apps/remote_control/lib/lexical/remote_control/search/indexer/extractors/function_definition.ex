defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionDefinition do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Range
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer
  alias Lexical.RemoteControl.Search.Subject

  @function_definitions [:def, :defp]

  def extract({definition, metadata, [{fn_name, _, args}, body]} = ast, %Reducer{} = reducer)
      when is_atom(fn_name) and definition in @function_definitions do
    detail_range = detail_range(reducer.analysis, metadata, body)

    {:ok, module} = RemoteControl.Analyzer.current_module(reducer.analysis, detail_range.start)

    arity =
      case args do
        list when is_list(list) ->
          length(list)

        nil ->
          0
      end

    type =
      case definition do
        :def -> :public_function
        :defp -> :private_function
      end

    mfa = Subject.mfa(module, fn_name, arity)
    %Block{} = block = Reducer.current_block(reducer)
    path = reducer.analysis.document.path

    block_range = block_range(reducer.analysis, ast)

    entry =
      Entry.block_definition(
        path,
        block,
        mfa,
        type,
        block_range,
        detail_range,
        Application.get_application(module)
      )

    {:ok, entry, ast}
  end

  def extract(_ast, _reducer) do
    :ignored
  end

  defp detail_range(%Analysis{} = analysis, def_metadata, block) do
    {line, column} = Metadata.position(def_metadata)

    {do_line, do_column} =
      case Sourceror.get_range(block) do
        %{start: do_meta} ->
          do_line = do_meta[:line]
          do_column = do_meta[:column]
          {do_line, do_column + 2}

        nil ->
          {line, column} = Metadata.position(def_metadata, :do)
          # add two for the do
          {line, column + 2}
      end

    start_pos = Position.new(analysis.document, line, column)
    do_pos = Position.new(analysis.document, do_line, do_column)
    Range.new(start_pos, do_pos)
  end

  defp block_range(%Analysis{} = analysis, def_ast) do
    case Lexical.Ast.Range.fetch(def_ast, analysis.document) do
      {:ok, range} -> range
      _ -> nil
    end
  end
end
