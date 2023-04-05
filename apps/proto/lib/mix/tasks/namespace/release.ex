defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  use Mix.Task
  @release_files ~w(start.script lexical.rel)
  @apps_to_rewrite ~w(remote_control common common_protocol server protocol proto)

  def run(_) do
    release = Mix.Release.from_config!(:lexical, Mix.Project.config(), [])
    Enum.each(@apps_to_rewrite, &update_app(release.path, release.version_path, &1))
    # namespace .app filenames because the filename is used as identifier by BEAM
    Enum.each(@apps_to_rewrite, &namespace_app_file(release.path, &1))
    Mix.Shell.IO.info("\nApplied namespace to release app.")
  end

  defp ebin_path(release_path, app_name) do
    [ebin_path] =
      [release_path, "lib", "#{app_name}-*", "ebin"]
      |> Path.join()
      |> Path.wildcard()

    ebin_path
  end

  defp app_file_path(release_path, app_name) do
    Path.join([ebin_path(release_path, app_name), "#{app_name}.app"])
  end

  defp update_app(release_path, release_version_path, app_name) do
    # Rename references in release scripts
    release_file_paths = Enum.map(@release_files, &Path.join([release_version_path, &1]))
    # Rename references in the dependencies of app files
    apps_file_paths = Enum.map(@apps_to_rewrite, &app_file_path(release_path, &1))
    paths = apps_file_paths ++ release_file_paths

    Enum.each(paths, &update_file_contents(&1, app_name))
  end

  defp update_file_contents(path, app_name) do
    contents = File.read!(path)
    # matches if preceding characters involves either of: , " [ { [:blank:]
    # this way it doesn't match on substrings or directory names
    updated_contents =
      String.replace(contents, ~r/([,"\[{[:blank:]])#{app_name}/, "\\1lx_#{app_name}")

    File.write!(path, updated_contents)
  end

  defp namespace_app_file(release_path, app_name) do
    ebin_path = ebin_path(release_path, app_name)
    app_file_path = app_file_path(release_path, app_name)
    namespaced_app_file = Path.join([ebin_path, "lx_" <> "#{app_name}.app"])
    :ok = File.rename(app_file_path, namespaced_app_file)
  end
end
