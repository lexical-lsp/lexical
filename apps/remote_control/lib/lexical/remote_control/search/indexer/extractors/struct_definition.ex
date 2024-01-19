defmodule Lexical.RemoteControl.Search.Indexer.Extractors.StructDefinition do
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def extract({:defstruct, _, [_fields]} = definition, %Reducer{} = reducer) do
    document = reducer.analysis.document
    block = Reducer.current_block(reducer)
    {:ok, current_module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    range = range(document, definition)

    entry =
      Entry.definition(
        document.path,
        block,
        current_module,
        :struct,
        range,
        Application.get_application(current_module)
      )

    {:ok, entry}
  end

  def extract(_, _) do
    :ignored
  end

  defp range(document, definition) do
    %{start: start_pos, end: end_pos} = Sourceror.get_range(definition)
    [line: start_line, column: start_column] = start_pos
    [line: end_line, column: end_column] = end_pos

    Range.new(
      Position.new(document, start_line, start_column),
      Position.new(document, end_line, end_column)
    )
  end
end
