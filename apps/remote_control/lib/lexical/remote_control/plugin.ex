defmodule Lexical.RemoteControl.Plugin do
  alias Lexical.Document
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Plugin

  require Logger
  import Messages

  def on_module_updated(plugin_module) do
    if Keyword.has_key?(plugin_module.__info__(:attributes), :lexical_plugin) do
      current_plugiuns = get()

      unless exists?(current_plugiuns, plugin_module) do
        plugin_module.init()
        add(current_plugiuns, plugin_module)
      end
    end
  end

  def diagnose(%Document{} = document) do
    diagnostics =
      :diagnostic
      |> get()
      |> Enum.map(fn realizer ->
        Plugin.Supervisor.async_nolink(fn -> realizer.(document) end)
      end)
      |> Enum.flat_map(&Task.await/1)

    diagnostic_message =
      file_diagnostics(
        project: RemoteControl.get_project(),
        uri: document.uri,
        diagnostics: diagnostics
      )

    RemoteControl.notify_listener(diagnostic_message)
  end

  def get do
    :persistent_term.get(__MODULE__, %{})
  end

  def get(plugin_type) do
    Map.get(get(), plugin_type, [])
  end

  def exists?(current_realizers, plugin_module) do
    plugin_module in Map.get(current_realizers, plugin_module.__plugin_type__())
  end

  def add(current_realizers, plugin_module) do
    plugin_type = plugin_module.__plugin_type__()

    realizer = realizer(plugin_type, plugin_module)

    realizers =
      Map.update(current_realizers, plugin_type, [realizer], fn realizers ->
        [realizer | realizers]
      end)

    :persistent_term.put(__MODULE__, realizers)
  end

  defp realizer(:diagnostic, plugin_module) do
    wrap_with_try_catch(fn %Document{} = document ->
      document
      |> plugin_module.diagnose()
      |> List.wrap()
    end)
  end

  defp realizer(_, plugin_module) do
    fn _ ->
      Logger.warn("Plugin module #{plugin_module} is not a valid plugin.")
      []
    end
  end

  defp wrap_with_try_catch(function) do
    fn arg ->
      try do
        function.(arg)
      rescue
        _ ->
          :ok
      catch
        :exit, _ ->
          :ok
      after
        []
      end
    end
  end
end
