defmodule Lexical.RemoteControl.Search.Indexer.Quoted do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  def index(%Document{} = document, quoted_ast) do
    {_, reducer} =
      Macro.prewalk(quoted_ast, Reducer.new(document, quoted_ast), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    {:ok, Reducer.entries(reducer)}
  end
end
