defmodule Lexical.RemoteControl.Plugin.Discovery do
  @moduledoc """
  Discovers any plugins in any loaded applications

  This module runs through the loaded applications and checks to see if any of them are lexical plugins.
  If a plugin is found, the app is then registered with the plugin system.

  If we're running in a namespaced build, we must apply the same namespace to the plugin's modules, or it
  will be looking for structs like `Lexical.Document`, and be passed in structs like `LXRelease.Document`,
  and the plugin will crash.
  """
  alias Lexical.Plugin.Runner
  alias Mix.Tasks.Namespace

  require Logger

  def run do
    for {app_name, _, _} <- :application.loaded_applications(),
        Runner.plugin_app?(app_name) do
      load_plugin_app(app_name)
    end

    Logger.info("Loaded #{inspect(Runner.enabled_plugins())}")
  end

  defp load_plugin_app(app_name) do
    with {:ok, modules} <- :application.get_key(app_name, :modules) do
      modules
      |> maybe_namespace()
      |> Runner.register_all()
    end
  end

  defp maybe_namespace(modules) when is_list(modules) do
    if namespaced?() do
      Enum.each(modules, fn module ->
        unload_module(module)
        namespace_module(module)
        Code.ensure_loaded(module)
      end)
    end

    modules
  end

  defp namespace_module(module) when is_atom(module) do
    module
    |> :code.which()
    |> List.to_string()
    |> Namespace.Transform.transform()
  end

  defp unload_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp namespaced? do
    case Code.ensure_loaded(LXRelease.Document) do
      {:module, _} -> true
      _ -> false
    end
  end
end
