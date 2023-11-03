defmodule Lexical.RemoteControl.Search.Indexer.Quoted do
  alias Lexical.Ast.Analysis
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def index(%Document{} = document, %Analysis{valid?: true} = analysis) do
    {_, reducer} =
      Macro.prewalk(analysis.ast, Reducer.new(document, analysis), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    {:ok, Reducer.entries(reducer)}
  end

  def index(%Document{}, %Analysis{valid?: false}) do
    {:ok, []}
  end
end
