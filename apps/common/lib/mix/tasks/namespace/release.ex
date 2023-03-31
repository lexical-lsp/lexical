defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  use Mix.Task
  @release_files ~w(start.script start_clean.script lexical.rel)
  @apps_to_rewrite ~w(remote_control)

  def run([release_path, release_version_path]) do
    Enum.map(@apps_to_rewrite, &update_app(release_path, release_version_path, &1))
  end

  defp update_app(release_path, release_version_path, app_name) do
    app_file_name = "#{app_name}.app"

    [ebin_path] =
      [release_path, "lib", "#{app_name}-*", "ebin"]
      |> Path.join()
      |> Path.wildcard()

    app_file_path = Path.join([ebin_path, app_file_name])
    release_file_paths = Enum.map(@release_files, &Path.join([release_version_path, &1]))
    paths = [app_file_path | release_file_paths]

    Enum.each(paths, &update_file_contents(&1, "remote_control"))

    # rename .app file because the filename is used as identifier by BEAM
    namespace_app_file(app_file_path)

    Mix.Shell.IO.info("\nApplied namespace to release app.")
  end

  defp update_file_contents(path, app_name) do
    contents = File.read!(path)
    # avoid replacing directory path with negative lookbehind:
    updated_contents = String.replace(contents, ~r/(?<!\/)#{app_name}/, "lx_#{app_name}")
    File.write!(path, updated_contents)
  end

  defp namespace_app_file(app_file_path) do
    app_file_dir = Path.dirname(app_file_path)
    app_file_name = Path.basename(app_file_path)
    namespaced_app_file = Path.join([app_file_dir, "lx_" <> app_file_name])
    :ok = File.rename(app_file_path, namespaced_app_file)
  end
end
