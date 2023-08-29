defmodule Mix.Tasks.Namespace.Path do
  alias Mix.Tasks.Namespace

  def apply(path) when is_list(path) do
    path
    |> List.to_string()
    |> apply()
    |> String.to_charlist()
  end

  def apply(path) when is_binary(path) do
    path
    |> Path.split()
    |> Enum.map(&replace_namespaced_apps/1)
    |> Path.join()
  end

  defp replace_namespaced_apps(path_component) do
    Enum.reduce(Namespace.app_names(), path_component, fn app_name, path ->
      if path == Atom.to_string(app_name) do
        app_name
        |> Namespace.Module.apply()
        |> Atom.to_string()
      else
        path
      end
    end)
  end
end
