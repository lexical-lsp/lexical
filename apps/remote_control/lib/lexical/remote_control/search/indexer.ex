defmodule Lexical.RemoteControl.Search.Indexer do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Indexer

  def index(%Project{} = project) do
    root_dir = Project.root_path(project)

    [root_dir, "**", "*.{ex,exs}"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      with {:ok, contents} <- File.read(path),
           {:ok, entries} <- Indexer.Source.index(path, contents) do
        entries
      else
        _ ->
          []
      end
    end)
  end

  def index(module) when is_atom(module) do
    Indexer.Module.index(module)
  end

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
end
