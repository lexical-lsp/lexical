defmodule Lexical.RemoteControl.Search.Indexer.Source.Reducer do
  @moduledoc """
  A module and struct that can reduce over elixir AST via Macro.prewalk/3

  The reducer keeps track of blocks and parent / child relationships so extractors don't have to concern themselves
  with the AST's overall structure, and can focus on extracting content from it.
  """

  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Extractors
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block

  defstruct [:analysis, :entries, :position, :ends_at, :blocks]

  @extractors [Extractors.Module, Extractors.Variable]

  def new(%Analysis{} = analysis) do
    %__MODULE__{
      analysis: analysis,
      entries: [],
      position: {0, 0},
      blocks: [Block.root()]
    }
  end

  def entries(%__MODULE__{} = reducer) do
    Enum.reverse(reducer.entries)
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
        |> apply_extractors(element)
    end
  end

  defp apply_extractors(%__MODULE__{} = reducer, element) do
    Enum.reduce(@extractors, {reducer, element}, fn detector_module, {reducer, element} ->
      case detector_module.extract(element, reducer) do
        {:ok, entry} ->
          reducer = push_entry(reducer, entry)
          {reducer, element}

        {:ok, entries, elem} when is_list(entries) ->
          reducer = push_entries(reducer, entries)
          {reducer, elem}

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

  def latest_block(%__MODULE__{} = reducer) do
    List.first(reducer.blocks)
  end

  def current_block(%__MODULE__{} = reducer) do
    {line, column} = reducer.position

    Enum.reduce_while(reducer.blocks, nil, fn
      %Block{ref: :root}, _acc ->
        {:halt, Block.root()}

      block, acc ->
        {starts_at_line, starts_at_column} = block.starts_at
        {ends_at_line, ends_at_column} = block.ends_at

        position_in_block? =
          cond do
            line == starts_at_line and column >= starts_at_column ->
              true

            line == ends_at_line and column <= ends_at_column ->
              true

            line > starts_at_line and line < ends_at_line ->
              true

            true ->
              false
          end

        if position_in_block? do
          {:halt, block}
        else
          {:cont, acc}
        end
    end)
  end

  defp push_block(%__MODULE__{} = reducer, %Block{} = block) do
    parent = List.first(reducer.blocks)
    block = %Block{block | parent_ref: parent.ref}
    %__MODULE__{reducer | blocks: [block | reducer.blocks]}
  end

  # you never pop the root block in a document
  defp pop_block(%__MODULE__{blocks: [%Block{ref: :root}]} = reducer), do: reducer

  defp pop_block(%__MODULE__{} = reducer) do
    [_ | rest] = reducer.blocks
    %__MODULE__{reducer | blocks: rest}
  end

  # The root block in the document goes on forever
  defp block_ended?(%__MODULE__{blocks: [%Block{ref: :root}]}), do: false

  defp block_ended?(%__MODULE__{} = reducer) do
    %Block{} = block = latest_block(reducer)

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

  defp push_entry(%__MODULE__{} = reducer, %Entry{} = entry) do
    %__MODULE__{reducer | entries: [entry | reducer.entries]}
  end

  defp push_entries(%__MODULE__{} = reducer, entries) do
    entries =
      Enum.reduce(entries, reducer.entries, fn entry, entries ->
        [entry | entries]
      end)

    %__MODULE__{reducer | entries: entries}
  end

  defp maybe_pop_block(%__MODULE__{} = reducer) do
    if block_ended?(reducer) do
      pop_block(reducer)
    else
      reducer
    end
  end
end
