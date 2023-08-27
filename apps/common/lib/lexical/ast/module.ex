defmodule Lexical.Ast.Module do
  @moduledoc """
  Module utilities
  """

  @doc """
  Formats a module name as a string.
  """
  @spec name(module()) :: String.t()
  def name(module) when is_atom(module) do
    module |> to_string() |> String.replace_prefix("Elixir.", "")
  end
end
