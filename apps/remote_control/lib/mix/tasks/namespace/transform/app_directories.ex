defmodule Mix.Tasks.Namespace.Transform.AppDirectories do
  alias Mix.Tasks.Namespace

  def apply_to_all(base_directory) do
    base_directory
    |> find_app_directories()
    |> Enum.each(&apply/1)
  end

  def apply(app_path) do
    namespaced_app_path = Namespace.Path.apply(app_path)

    with {:ok, _} <- File.rm_rf(namespaced_app_path) do
      File.rename!(app_path, namespaced_app_path)
    end
  end

  defp find_app_directories(base_directory) do
    app_globs = Enum.join(Namespace.app_names(), "*,")

    [base_directory, "lib", "{" <> app_globs <> "*}"]
    |> Path.join()
    |> Path.wildcard()
  end
end
