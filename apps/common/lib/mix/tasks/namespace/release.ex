defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  use Mix.Task

  def run(_) do
    release = Mix.Release.from_config!(:lexical, Mix.Project.config(), [])
    release_path = release.path
    release_version_path = release.version_path

    app_names = ~w(remote_control common common_protocol server protocol)a
    app_paths = Enum.map(app_names, fn app ->
      vsn = Mix.Project.in_project(app, Mix.Project.apps_paths()[app],
        fn _ -> Mix.Project.config()[:version]
      end)
      Path.join([release_path, "lib", "#{app}-#{vsn}", "ebin", "#{app}.app"])
    end)

    release_files = ~w(start.script lexical.rel)
    script_paths = Enum.map(release_files, &Path.join([release_version_path, &1]))

    paths = script_paths ++ app_paths

    Enum.each(paths, fn p ->
      string = File.read!(p)
      # avoid replacing directory path with negative lookbehind:
      string = String.replace(string, ~r/(?<!\/)remote_control/, "lx_remote_control")
      string = String.replace(string, ~r/(?<!\/)common(?!_)/, "lx_common")
      string = String.replace(string, ~r/(?<!\/)common_protocol/, "lx_common_protocol")
      string = String.replace(string, ~r/(?<!\/)server/, "lx_server")
      string = String.replace(string, ~r/(?<![\/_])protocol/, "lx_protocol")
      File.write!(p, string)
    end)

    Enum.each(app_paths, fn app_path ->
      { app_file, dirlist } = Path.split(app_path) |> List.pop_at(-1)
      lx_name = "lx_#{app_file}"
      lx_app_path = Path.join(dirlist ++ [lx_name])
      # rename .app file because the filename is used as identifier by BEAM
      :ok = File.rename(app_path, lx_app_path)
    end)

    Mix.Shell.IO.info("\nApplied namespace to release app.")
  end
end
