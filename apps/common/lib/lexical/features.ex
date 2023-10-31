defmodule Lexical.Features do
  @indexing_enabled "INDEXING_ENABLED" |> System.get_env("") |> String.trim() |> String.downcase()

  def indexing_enabled? do
    @indexing_enabled in ~w(1 true)
  end
end
