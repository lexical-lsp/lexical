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
      string_name = Atom.to_string(app_name)

      namespaced_name =
        app_name
        |> Namespace.Module.apply()
        |> Atom.to_string()

      if String.contains?(path, namespaced_name) do
        path
      else
        String.replace(path, string_name, namespaced_name)
      end
    end)
  end
end
