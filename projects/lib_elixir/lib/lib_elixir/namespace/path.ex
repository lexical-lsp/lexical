defmodule LibElixir.Namespace.Path do
  alias LibElixir.Namespace

  def apply(path) when is_list(path) do
    path
    |> List.to_string()
    |> apply()
    |> String.to_charlist()
  end

  def apply(path) when is_binary(path) do
    Path.join([
      Path.dirname(path),
      path |> Path.basename() |> replace_namespaced_apps()
    ])
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
