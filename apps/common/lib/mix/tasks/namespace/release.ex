defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  use Mix.Task

  def run([release_version_path, remote_control_ebin]) do
    release_files = ~w(start.script lexical.rel)
    remote_app = Path.join([remote_control_ebin, "remote_control.app"])
    paths = [remote_app | Enum.map(release_files, &Path.join([release_version_path, &1]))]

    Enum.each(paths, fn p ->
      string = File.read!(p)
      # avoid replacing directory path with negative lookbehind:
      string = String.replace(string, ~r/(?<!\/)remote_control/, "lx_remote_control")
      File.write!(p, string)
    end)

    # rename .app file because the filename is used as identifier by BEAM
    lx_app = Path.join([remote_control_ebin, "lx_remote_control.app"])
    :ok = File.rename(remote_app, lx_app)

    Mix.Shell.IO.info("\nApplied namespace to release app.")
  end
end
