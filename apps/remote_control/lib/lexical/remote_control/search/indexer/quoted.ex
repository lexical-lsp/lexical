defmodule Lexical.RemoteControl.Search.Indexer.Quoted do
  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def index(%Analysis{valid?: true} = analysis) do
    {_, reducer} =
      Macro.prewalk(analysis.ast, Reducer.new(analysis), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    {:ok, Reducer.entries(reducer)}
  end

  def index(%Analysis{valid?: false}) do
    {:ok, []}
  end
end
