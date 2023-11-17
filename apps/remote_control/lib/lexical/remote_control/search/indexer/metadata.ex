defmodule Lexical.RemoteControl.Search.Indexer.Metadata do
  @moduledoc """
  Utilities for extracting location information from AST metadata nodes.
  """
  alias Sourceror.Zipper

  # fn -> things end
  def location({:->, metadata, [[], _]}) do
    {:expression, position(metadata)}
  end

  def location({:->, meta, [left, {:__block__, right_meta, right_blocks}]}) do
    block_start = arrow_start_position(left)

    if pos = position(right_meta, :closing) do
      block_end = pos
      {:block, position(meta), block_start, block_end}
    else
      block_end = arrow_last_position(right_meta, right_blocks)
      {:block, position(meta), block_start, block_end}
    end
  end

  # fn x -> x end
  def location({:->, meta, [left, {_, right_meta, nil}]}) do
    block_start = arrow_start_position(left)
    {:block, position(meta), block_start, position(right_meta)}
  end

  def location({_, metadata, _}) do
    if Keyword.has_key?(metadata, :do) do
      position = position(metadata)
      block_start = position(metadata, :do)
      block_end = position(metadata, :end_of_expression) || position(metadata, :end)
      {:block, position, block_start, block_end}
    else
      {:expression, position(metadata)}
    end
  end

  def location(_unknown) do
    {:expression, nil}
  end

  def position(keyword) do
    line = Keyword.get(keyword, :line)
    column = Keyword.get(keyword, :column)

    case {line, column} do
      {nil, nil} ->
        nil

      position ->
        position
    end
  end

  def position(keyword, key) do
    keyword
    |> Keyword.get(key, [])
    |> position()
  end

  defp arrow_start_position([{:when, _, blocks} | _]) do
    arrow_start_position(blocks)
  end

  defp arrow_start_position(node) do
    start_node = %Zipper{node: node} |> Zipper.leftmost() |> Zipper.next() |> Zipper.node()
    {_, start_meta, _} = start_node
    position(start_meta)
  end

  def arrow_last_position(right_meta, right_blocks) do
    last_meta = arrow_last_meta(right_meta, right_blocks)

    position(last_meta, :end_of_expression) ||
      position(last_meta, :closing) ||
      position(last_meta)
  end

  defp arrow_last_meta(right_meta, blocks) when is_list(blocks) do
    blocks |> List.last() |> then(&arrow_last_meta(right_meta, &1))
  end

  defp arrow_last_meta(_right_meta, {_, meta, _}) do
    meta
  end

  # fn x -> «1» end
  defp arrow_last_meta(right_meta, _token) do
    right_meta
  end
end
