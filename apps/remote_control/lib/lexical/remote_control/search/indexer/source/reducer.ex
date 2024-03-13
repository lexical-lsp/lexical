defmodule Lexical.RemoteControl.Search.Indexer.Source.Reducer do
  @moduledoc """
  A module and struct that can reduce over elixir AST via Macro.prewalk/3

  The reducer keeps track of blocks and parent / child relationships so extractors don't have to concern themselves
  with the AST's overall structure, and can focus on extracting content from it.
  """

  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Extractors
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block

  defstruct [:analysis, :entries, :position, :blocks, :block_hierarchy, extractors: []]

  @extractors [
    Extractors.Module,
    Extractors.ModuleAttribute,
    Extractors.FunctionDefinition,
    Extractors.FunctionReference,
    Extractors.StructDefinition,
    Extractors.StructReference
  ]

  def new(%Analysis{} = analysis, extractors \\ nil) do

    %__MODULE__{
      analysis: analysis,
      block_hierarchy: %{root: %{}},
      blocks: [Block.root()],
      entries: [],
      extractors: extractors || @extractors,
      position: {0, 0}
    }
  end

  def human_location(%__MODULE__{} = reducer) do
    {line, column} = reducer.position
    path = reducer.analysis.document.path
    "#{path} #{line}:#{column}"
  end

  def entries(%__MODULE__{} = reducer) do
    [hierarchy(reducer) | Enum.reverse(reducer.entries)]
  end

  def skip(meta) do
    Keyword.put(meta, :__skipped__, true)
  end

  def skip?({_, meta, _}) do
    Keyword.get(meta, :__skipped__, false)
  end

  def skip?(_), do: false

  def reduce(%__MODULE__{} = reducer, element) do
    if skip?(element) do
      {reducer, element}
    else
      do_reduce(reducer, element)
    end
  end

  def position(%__MODULE__{} = reducer) do
    {line, column} = reducer.position
    Position.new(reducer.analysis.document, line, column)
  end

  defp hierarchy(%__MODULE__{} = reducer) do
    Entry.block_structure(reducer.analysis.document.path, reducer.block_hierarchy)
  end

  defp do_reduce(%__MODULE__{} = reducer, element) do
    case Metadata.location(element) do
      {:block, position, block_start, block_end} ->
        block = Block.new(block_start, block_end)

        reducer
        |> update_position(position)
        |> maybe_pop_block()
        |> push_block(block)
        |> apply_extractors(element)

      {:expression, position} ->
        reducer
        |> update_position(position)
        |> maybe_pop_block()
        |> apply_extractors(element)
    end
  end

  defp apply_extractors(%__MODULE__{} = reducer, element) do
    Enum.reduce(reducer.extractors, {reducer, element}, fn detector_module, {reducer, element} ->
      case detector_module.extract(element, reducer) do
        {:ok, entry} ->
          reducer = push_entry(reducer, entry)
          {reducer, element}

        {:ok, entry, elem} ->
          reducer = push_entry(reducer, entry)

          {reducer, elem}

        :ignored ->
          {reducer, element}
      end
    end)
  end

  defp update_position(%__MODULE__{} = reducer, nil) do
    reducer
  end

  defp update_position(%__MODULE__{} = reducer, position) do
    Map.put(reducer, :position, position)
  end

  def current_block(%__MODULE__{} = reducer) do
    List.first(reducer.blocks)
  end

  defp push_block(%__MODULE__{} = reducer, %Block{} = block) do
    parent = current_block(reducer)
    block = %Block{block | parent_id: parent.id}
    id_path = Enum.reduce(reducer.blocks, [], fn block, acc -> [block.id | acc] end)

    hierarchy =
      update_in(reducer.block_hierarchy, id_path, fn current ->
        Map.put(current, block.id, %{})
      end)

    %__MODULE__{reducer | blocks: [block | reducer.blocks], block_hierarchy: hierarchy}
  end

  # you never pop the root block in a document
  defp pop_block(%__MODULE__{blocks: [%Block{id: :root}]} = reducer), do: reducer

  defp pop_block(%__MODULE__{} = reducer) do
    [_ | rest] = reducer.blocks
    %__MODULE__{reducer | blocks: rest}
  end

  # The root block in the document goes on forever
  defp block_ended?(%__MODULE__{blocks: [%Block{id: :root}]}), do: false

  defp block_ended?(%__MODULE__{} = reducer) do
    %Block{} = block = current_block(reducer)

    {ends_at_line, ends_at_column} = block.ends_at

    {current_line, current_column} = reducer.position

    cond do
      current_line == ends_at_line and current_column > ends_at_column ->
        true

      current_line > ends_at_line ->
        true

      true ->
        false
    end
  end

  defp push_entry(%__MODULE__{} = reducer, entries) when is_list(entries) do
    Enum.reduce(entries, reducer, &push_entry(&2, &1))
  end

  defp push_entry(%__MODULE__{} = reducer, %Entry{} = entry) do
    %__MODULE__{reducer | entries: [entry | reducer.entries]}
  end

  defp push_entry(%__MODULE__{} = reducer, _), do: reducer

  defp maybe_pop_block(%__MODULE__{} = reducer) do
    if block_ended?(reducer) do
      reducer
      |> pop_block()
      |> maybe_pop_block()
    else
      reducer
    end
  end
end
