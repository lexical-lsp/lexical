defmodule Lexical.RemoteControl.Search.Indexer.Extractors.ModuleAttribute do
  @moduledoc """
  Extracts module attribute definitions and references from AST
  """

  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer
  alias Lexical.RemoteControl.Search.Subject

  require Logger

  # Finds module attribute usages
  def extract({:@, _, [{attr_name, _, nil}]}, %Reducer{} = reducer) do
    block = Reducer.current_block(reducer)

    {:ok, current_module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))

    reference =
      Entry.reference(
        reducer.analysis.document.path,
        block,
        Subject.module_attribute(current_module, attr_name),
        :module_attribute,
        reference_range(reducer, attr_name),
        Application.get_application(current_module)
      )

    {:ok, reference}
  end

  # an attribute being typed above an already existing attribute will have the name `@`, which we ignore
  # example:
  # @|
  # @callback foo() :: :ok
  def extract({:@, _, [{:@, _, _attr_value}]}, %Reducer{}) do
    :ignored
  end

  # Finds module attribute definitions @foo 3
  def extract({:@, _, [{attr_name, _, _attr_value}]} = attr, %Reducer{} = reducer) do
    block = Reducer.current_block(reducer)

    {:ok, current_module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))

    definition =
      Entry.definition(
        reducer.analysis.document.path,
        block,
        Subject.module_attribute(current_module, attr_name),
        :module_attribute,
        definition_range(reducer, attr),
        Application.get_application(current_module)
      )

    {:ok, definition}
  end

  def extract(_, _) do
    :ignored
  end

  defp reference_range(%Reducer{} = reducer, attr_name) do
    document = reducer.analysis.document

    name_length =
      attr_name
      |> Atom.to_string()
      |> String.length()

    {start_line, start_column} = reducer.position

    # add 1 to include the @ character
    end_column = start_column + name_length + 1

    Range.new(
      Position.new(document, start_line, start_column),
      Position.new(document, start_line, end_column)
    )
  end

  defp definition_range(%Reducer{} = reducer, attr_ast) do
    document = reducer.analysis.document

    [line: start_line, column: start_column] = Sourceror.get_start_position(attr_ast)

    end_line = Sourceror.get_end_line(attr_ast)
    {:ok, line_text} = Lexical.Document.fetch_text_at(document, end_line)
    # add one because lsp positions are one-based
    end_column = String.length(line_text) + 1

    Range.new(
      Position.new(document, start_line, start_column),
      Position.new(document, end_line, end_column)
    )
  end
end
