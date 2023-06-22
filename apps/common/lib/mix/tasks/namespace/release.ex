defmodule Mix.Tasks.Namespace.Release do
  @moduledoc """
  `remote_control.app` must be namespaced too
  """
  alias Mix.Tasks.Namespace
  use Mix.Task

  @release_files ~w(start.script lexical.rel start_clean.script)
  @boot_files ~w(start.boot start_clean.boot)

  def run(_) do
    apps_to_namespace = Namespace.apps_to_namespace()
    release = Mix.Release.from_config!(:lexical, Mix.Project.config(), [])

    Enum.each(
      apps_to_namespace,
      &update_app(release.path, release.version_path, apps_to_namespace, &1)
    )

    # namespace .app filenames because the filename is used as identifier by BEAM
    Enum.each(apps_to_namespace, &namespace_app_file(release.path, &1))
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

  defp update_app(release_path, release_version_path, referencing_apps, app_name) do
    # Rename references in release scripts
    release_file_paths = Enum.map(@release_files, &Path.join([release_version_path, &1]))
    # Rename references in the dependencies of app files
    apps_file_paths = Enum.map(referencing_apps, &app_file_path(release_path, &1))
    paths = apps_file_paths ++ release_file_paths

    Enum.each(paths, &update_file_contents(&1, app_name))
  end

  defp update_file_contents(path, app_name) do
    contents = File.read!(path)
    updated_contents = update_script_contents(contents, app_name)
    File.write!(path, updated_contents)
  end

  defp update_script_contents(contents, app_name) do
    # matches if preceding characters involves either of: , " [ { [:blank:]
    # this way it doesn't match on substrings or directory names
    contents = String.replace(contents, ~r/([,"\[{[:blank:]])#{app_name}/, "\\1lx_#{app_name}")

    Enum.reduce(Namespace.root_modules(), contents, fn root_module, contents ->
      new_modules = root_module |> Namespace.Module.apply() |> to_string()
      String.replace(contents, to_string(root_module), new_modules)
    end)
  end

  defp namespace_app_file(release_path, app_name) do
    ebin_path = ebin_path(release_path, app_name)
    app_file_path = app_file_path(release_path, app_name)
    namespaced_app_file = Path.join([ebin_path, "lx_" <> "#{app_name}.app"])
    :ok = File.rename(app_file_path, namespaced_app_file)
  end

  defp update_boot_file(path) do
    term = path |> File.read!() |> :erlang.binary_to_term()
    {script, script_info, module_infos} = term
    new_module_infos = Enum.map(module_infos, &update_module_list/1)
    namespaced_contents = :erlang.term_to_binary({script, script_info, new_module_infos})
    File.write!(path, namespaced_contents)
  end

  defp update_module_list({load_info, modules}) when is_list(modules) do
    new_modules = apply_namespace(modules)
    {load_info, new_modules}
  end

  defp update_module_list({:apply, {:application, mode, [{:application, app_name, app_keys}]}}) do
    new_app_keys = Enum.map(app_keys, &namespace_app_key/1)

    {:apply, {:application, mode, [{:application, app_name, new_app_keys}]}}
  end

  defp update_module_list(original) do
    original
  end

  defp namespace_app_key({:modules, module_list}) do
    namespaced_modules = Enum.map(module_list, &Namespace.Module.apply/1)
    {:modules, namespaced_modules}
  end

  defp namespace_app_key({:mod, {app_module, args}}) do
    {:mod, {Namespace.Module.apply(app_module), args}}
  end

  defp namespace_app_key(app_key) do
    app_key
  end

  defp apply_namespace(modules_list) when is_list(modules_list) do
    Enum.map(modules_list, &apply_namespace/1)
  end

  defp apply_namespace(module) when is_atom(module) do
    Namespace.Module.apply(module)
  end

  defp apply_namespace(original) do
    original
  end
end
