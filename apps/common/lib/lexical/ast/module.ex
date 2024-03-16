defmodule Lexical.Ast.Module do
  @moduledoc """
  Module utilities
  """

  @doc """
  Formats a module name as a string.
  """
  @spec name(module() | Macro.t() | String.t()) :: String.t()
  def name([{:__MODULE__, _, _} | rest]) do
    [__MODULE__ | rest]
    |> Module.concat()
    |> name()
  end

  def name(module_name) when is_list(module_name) do
    module_name
    |> Module.concat()
    |> name()
  end

  def name(module_name) when is_binary(module_name) do
    module_name
  end

  def name(module_name) when is_atom(module_name) do
    module_name
    |> inspect()
    |> name()
  end
end
