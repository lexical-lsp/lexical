defmodule LibElixir.Namespace.Transform.AppDirectories do
  alias LibElixir.Namespace

  def apply_to_all(base_directory) do
    base_directory
    |> find_app_directories()
    |> Enum.each(&apply/1)
  end

  def apply(app_path) do
    namespaced_app_path = Namespace.Path.apply(app_path)
    File.rename!(app_path, namespaced_app_path)
  end

  defp find_app_directories(base_directory) do
    [base_directory]
  end
end
