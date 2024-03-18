defmodule Lexical.RemoteControl.Search.Indexer.Extractors.ExUnit do
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Formats
  alias Lexical.RemoteControl.Analyzer
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  require Logger

  # setup block i.e. setup do... or setup arg do...
  def extract({setup_fn, _, args} = setup, %Reducer{} = reducer)
      when setup_fn in [:setup, :setup_all] and length(args) > 0 do
    {:ok, module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    arity = arity_for(args)
    subject = Formats.mfa(module, setup_fn, arity)

    entry = entry(reducer, setup, :"ex_unit_#{setup_fn}", subject)

    {:ok, entry}
  end

  # Test block test "test name" do ... or test "test name", arg do
  def extract({:test, _, [{_, _, [test_name]} | _] = args} = test, %Reducer{} = reducer) do
    {:ok, module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    arity = arity_for(args)
    module_name = Formats.module(module)
    subject = "#{module_name}.[\"#{test_name}\"]/#{arity}"

    entry = entry(reducer, test, :ex_unit_test, subject)

    {:ok, entry}
  end

  # describe blocks
  def extract({:describe, _, [{_, _, [describe_name]} | _] = args} = test, %Reducer{} = reducer) do
    {:ok, module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    arity = arity_for(args)
    module_name = Formats.module(module)
    subject = "#{module_name}[\"#{describe_name}\"]/#{arity}"

    entry = entry(reducer, test, :ex_unit_describe, subject)

    {:ok, entry}
  end

  def extract(_ign, _) do
    :ignored
  end

  defp entry(%Reducer{} = reducer, ast, type, subject) do
    path = reducer.analysis.document.path
    block = Reducer.current_block(reducer)

    {:ok, module} = Analyzer.current_module(reducer.analysis, Reducer.position(reducer))
    app = Application.get_application(module)

    Entry.block_definition(path, block, subject, type, block_range(reducer.analysis, ast), app)
  end

  defp block_range(%Analysis{} = analysis, ast) do
    case Metadata.location(ast) do
      {:block, {start_line, start_column}, {do_line, do_column}, _} ->
        Range.new(
          Position.new(analysis.document, start_line, start_column),
          Position.new(analysis.document, do_line, do_column + 2)
        )

      {:expression, {start_line, start_column}} ->
        %{end: [line: end_line, column: end_column]} = Sourceror.get_range(ast)

        Range.new(
          Position.new(analysis.document, start_line, start_column),
          Position.new(analysis.document, end_line, end_column)
        )
    end
  end

  defp arity_for([{:__block__, _meta, labels}]) do
    length(labels)
  end

  defp arity_for(args) when is_list(args) do
    length(args)
  end

  defp arity_for(_), do: 0
end
