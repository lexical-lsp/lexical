defmodule Lexical.RemoteControl.CodeIntelligence.Structs do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Module.Loader
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Store

  def for_project do
    if Mix.Project.get() do
      {:ok, structs_from_index()}
    else
      RemoteControl.Mix.in_project(fn _ -> structs_from_index() end)
    end
  end

  defp structs_from_index do
    # This might be a performance / memory issue on larger projects. It
    # iterates through all modules, loading each as necessary and then removing them
    # if they're not already loaded to try and claw back some memory
    entries =
      case Store.exact(type: :struct, subtype: :definition) do
        {:ok, entries} -> entries
        _ -> []
      end

    for %Entry{subject: struct_module} <- entries,
        Loader.ensure_loaded?(struct_module) do
      struct_module
    end
  end
end
