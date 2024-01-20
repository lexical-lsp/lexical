defmodule Lexical.RemoteControl.Search.Indexer.Extractors.StructDefinition do
  alias Lexical.Ast
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def extract({:defstruct, _, [_fields]} = definition, %Reducer{} = reducer) do
    document = reducer.analysis.document
    block = Reducer.current_block(reducer)
    {:ok, current_module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    range = Ast.Range.fetch!(definition, document)

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
end
