defmodule Lexical.RemoteControl.Search.Indexer do
  alias Lexical.RemoteControl.Search.Indexer

  def index_all do
    :code.all_available()
    |> Enum.flat_map(fn {module_name, _, _} ->
      module = List.to_atom(module_name)

      case index(module) do
        {:ok, indexed} ->
          indexed

        _ ->
          []
      end
    end)
  end

  def index(module) when is_atom(module) do
    Indexer.Module.index(module)
  end
end
