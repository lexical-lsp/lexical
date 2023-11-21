defmodule Lexical.RemoteControl.Search.Indexer.Extractors.FunctionDefinition do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  @function_definitions [:def, :defp]

  def extract({definition, metadata, [{fn_name, _, args}, _body]} = ast, %Reducer{} = reducer)
      when is_atom(fn_name) and definition in @function_definitions do
    range = get_extent(reducer.analysis, metadata)

    module =
      reducer.analysis
      |> Analysis.aliases_at(range.start)
      |> Map.get(:__MODULE__)

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
        block.ref,
        block.parent_ref,
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

  defp get_extent(%Analysis{} = analysis, metadata) do
    {line, column} = Metadata.position(metadata)

    {end_line, end_column} =
      with nil <- Metadata.position(metadata, :do),
           nil <- Metadata.position(metadata, :end_of_expression),
           {:ok, line_text} <- Document.fetch_text_at(analysis.document, line) do
        end_column = String.length(line_text)
        {line, end_column}
      end

    start_pos = Position.new(analysis.document, line, column)
    end_pos = Position.new(analysis.document, end_line, end_column)
    Range.new(start_pos, end_pos)
  end
end
