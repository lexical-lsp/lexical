defmodule LibElixir.Namespace.DebugInfo do
  @moduledoc false

  alias LibElixir.Namespace

  def rewrite(atom) when is_atom(atom) do
    rewrite_module(atom)
  end

  def rewrite(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> rewrite()
    |> List.to_tuple()
  end

  def rewrite(list) when is_list(list) do
    Enum.map(list, &rewrite/1)
  end

  def rewrite(map) when is_map(map) do
    map
    |> Enum.to_list()
    |> rewrite()
    |> Map.new()
  end

  def rewrite(other), do: other

  defp rewrite_module(atom) when is_atom(atom) do
    Namespace.Module.apply(atom)
  end
end
