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

  @doc """
  local module name is the last part of a module name

  ## Examples:
      iex> local_name('Lexical.Ast.Module')
      "Module"
  """
  def local_name(entity) when is_list(entity) do
    entity
    |> to_string()
    |> local_name()
  end

  def local_name(entity) when is_binary(entity) do
    entity
    |> String.split(".")
    |> List.last()
  end
end
