defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionDefinition do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.Identifier
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  @function_definitions [:def, :defp]

  def extract({definition, metadata, [{fn_name, _, args}, body]} = ast, %Reducer{} = reducer)
      when is_atom(fn_name) and definition in @function_definitions do
    range = get_definition_range(reducer.analysis, metadata, body)

    {:ok, module} =
      RemoteControl.Analyzer.expand_alias([:__MODULE__], reducer.analysis, range.start)

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

    mfa = "#{Formats.module(module)}.#{fn_name}/#{arity}"
    %Block{} = block = Reducer.current_block(reducer)

    entry =
      Entry.definition(
        reducer.analysis.document.path,
        Identifier.next_global!(),
        block.parent_id,
        mfa,
        type,
        range,
        Application.get_application(module)
      )

    {:ok, entry, ast}
  end

  def extract(_ast, _reducer) do
    :ignored
  end

  defp get_definition_range(%Analysis{} = analysis, def_metadata, block) do
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
end
