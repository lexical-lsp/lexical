defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  alias Mix.Tasks.Namespace.Abstract

  use Mix.Task
  @release_files ~w(start.script lexical.rel start_clean.script)
  @boot_files ~w(start.boot start_clean.boot)
  @apps_to_rewrite ~w(remote_control common server protocol proto lexical_shared lexical_plugin)

  def run(_) do
    release = Mix.Release.from_config!(:lexical, Mix.Project.config(), [])
    Enum.each(@apps_to_rewrite, &update_app(release.path, release.version_path, &1))
    # namespace .app filenames because the filename is used as identifier by BEAM
    Enum.each(@apps_to_rewrite, &namespace_app_file(release.path, &1))
    Enum.each(@boot_files, &update_boot_file(boot_file_path(release.version_path, &1)))
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

  defp boot_file_path(release_version_path, boot_name) do
    Path.join(release_version_path, boot_name)
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
      contents
      |> String.replace(~r/([,"\[{[:blank:]])#{app_name}/, "\\1lx_#{app_name}")
      |> String.replace("Elixir.Lexical", "Elixir.LXRelease")

    File.write!(path, updated_contents)
  end

  defp namespace_app_file(release_path, app_name) do
    ebin_path = ebin_path(release_path, app_name)
    app_file_path = app_file_path(release_path, app_name)
    namespaced_app_file = Path.join([ebin_path, "lx_" <> "#{app_name}.app"])
    :ok = File.rename(app_file_path, namespaced_app_file)
  end

  defp update_boot_file(path) do
    binary = path |> File.read!() |> :erlang.binary_to_term()
    {script, script_info, module_infos} = binary

    new_module_infos =
      Enum.map(module_infos, fn
        {load_info, modules} when is_list(modules) ->
          new_modules =
            Enum.map(modules, fn
              module when is_atom(module) -> Abstract.rewrite_module(module)
              other -> other
            end)

          {load_info, new_modules}

        {:apply, app} ->
          rewrite_deep_modules({:apply, app})

        other ->
          other
      end)

    updated_contents = :erlang.term_to_binary({script, script_info, new_module_infos})
    File.write!(path, updated_contents)
  end

  def rewrite_deep_modules({:apply, {:application, mode, [{:application, app_name, app_info}]}}) do
    new_modules = for module <- app_info[:modules], do: Abstract.rewrite_module(module)
    new_app_info = Keyword.put(app_info, :modules, new_modules)
    {:apply, {:application, mode, [{:application, app_name, new_app_info}]}}
  end

  def rewrite_deep_modules({:apply, other}) do
    {:apply, other}
  end
end
