defmodule Lexical.Server.Boot do
  @moduledoc """
  This module is called when the server starts by the start script.

  Packaging will ensure that config.exs and runtime.exs will be visible to the `:code` module
  """
  @env Mix.env()
  @target Mix.target()
  @dep_apps Enum.map(Mix.Dep.cached(), & &1.app)

  def start do
    {:ok, _} = Application.ensure_all_started(:mix)
    Application.stop(:logger)
    load_config()
    Application.ensure_all_started(:logger)

    Enum.each(@dep_apps, &load_app_modules/1)
    Application.ensure_all_started(:server)
  end

  defp load_config do
    config = read_config("config.exs")
    runtime = read_config("runtime.exs")
    merged_config = Config.Reader.merge(config, runtime)
    apply_config(merged_config)
  end

  defp apply_config(configs) do
    for {app_name, keywords} <- configs,
        {config_key, config_value} <- keywords do
      Application.put_env(app_name, config_key, config_value)
    end
  end

  defp read_config(file_name) do
    case where_is_file(String.to_charlist(file_name)) do
      {:ok, path} ->
        Config.Reader.read!(path, env: @env, target: @target)

      _ ->
        []
    end
  end

  defp where_is_file(file_name) do
    case :code.where_is_file(file_name) do
      :non_existing ->
        :error

      path ->
        {:ok, List.to_string(path)}
    end
  end

  defp load_app_modules(app_name) do
    Application.ensure_loaded(app_name)

    with {:ok, modules} <- :application.get_key(app_name, :modules) do
      Enum.each(modules, &Code.ensure_loaded!/1)
    end
  end
end
