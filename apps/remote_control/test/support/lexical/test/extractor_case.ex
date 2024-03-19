defmodule Lexical.Test.ExtractorCase do
  alias Lexical.Document
  alias Lexical.RemoteControl.Search.Indexer

  use ExUnit.CaseTemplate
  import Lexical.Test.CodeSigil

  using do
    quote do
      import Lexical.Test.CodeSigil
      import Lexical.Test.RangeSupport
      import unquote(__MODULE__)
    end
  end

  def do_index(source, filter, extractors \\ nil)

  def do_index(source, filter, extractors) when is_binary(source) do
    path = "/foo/bar/baz.ex"
    doc = Document.new("file:///#{path}", source, 1)

    case Indexer.Source.index(path, source, extractors) do
      {:ok, indexed_items} ->
        indexed_items = Enum.filter(indexed_items, filter)
        {:ok, indexed_items, doc}

      error ->
        error
    end
  end

  def do_index(quoted_source, filter, extractors) do
    source_string = Macro.to_string(quoted_source)
    do_index(source_string, filter, extractors)
  end

  def in_a_module(code, module_name \\ "Parent") do
    ~q[
    defmodule #{module_name} do
      #{code}
    end
    ]
  end

  def in_a_module_function(code) do
    ~q[
      def something do
        #{code}
      end
    ]
    |> in_a_module()
  end
end
