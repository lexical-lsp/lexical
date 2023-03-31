defmodule Lexical.Server.CodeIntelligence.Completion.Builder do
  alias Lexical.Completion.Builder
  alias Lexical.Protocol.Types.Completion
  @behaviour Builder

  @impl Builder
  def snippet(snippet_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, snippet_text)
    |> Keyword.put(:insert_text_format, :snippet)
    |> Completion.Item.new()
  end

  @impl Builder
  def plain_text(insert_text, options \\ []) do
    options
    |> Keyword.put(:insert_text, insert_text)
    |> Completion.Item.new()
  end

  @impl Builder
  def fallback(nil, fallback), do: fallback
  def fallback("", fallback), do: fallback
  def fallback(detail, _), do: detail

  @impl Builder
  def boost(text, amount \\ 5)

  def boost(text, amount) when amount in 0..10 do
    boost_char = ?* - amount
    IO.iodata_to_binary([boost_char, text])
  end

  def boost(text, _) do
    boost(text, 0)
  end
end
