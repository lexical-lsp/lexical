defmodule Lexical.RemoteControl.PluginServer do
  defmodule State do
    defstruct plugins: []
  end

  alias Lexical.Document
  alias Lexical.Formats
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages

  require Logger

  import Messages

  use GenServer

  def enhance(%Project{} = project) do
    GenServer.cast(__MODULE__, {:enhance_project, project})
  end

  def enhance(%Project{} = project, %Document{} = document) do
    GenServer.cast(__MODULE__, {:enhance_file, project, document})
  end

  # Public
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %State{plugins: plugins()}}
  end

  @impl true
  def handle_cast({:enhance_file, project, document}, %State{plugins: plugins} = state) do
    for plugin <- plugins, do: plugin.init()

    for plugin <- state.plugins do
      source_string = Document.to_string(document)
      path = document.path |> Path.relative_to_cwd()

      source_string
      |> plugin.issues(path)
      |> publish(project, document.uri)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:enhance_project, project}, %State{plugins: plugins} = state) do
    for plugin <- plugins, do: plugin.init()

    for plugin <- state.plugins do
      {t, _} =
        :timer.tc(fn ->
          publish(plugin.issues(), project)
        end)

      Logger.info("Plugin #{plugin} enhance project diagnostics took #{Formats.time(t)} ")
    end

    {:noreply, state}
  end

  @from "Plugin"

  defp publish(result, project, uri) do
    diagnostics = file_diagnostics(project: project, uri: uri, diagnostics: result, from: @from)
    RemoteControl.notify_listener(diagnostics)
    result
  end

  defp publish(result, project) do
    diagnostics = project_diagnostics(project: project, diagnostics: result, from: @from)
    RemoteControl.notify_listener(diagnostics)
    result
  end

  defp plugins do
    config = config_file()

    if config do
      config
      |> Config.Reader.read!(env: :test)
      |> get_in([:lexical, :plugins])
      |> Kernel.||([])
    else
      []
    end
  end

  defp config_file do
    config_file("config/config.exs")
  end

  defp config_file(config_file) do
    config_file = if File.exists?(config_file), do: config_file, else: "../../config/config.exs"
    if File.exists?(config_file), do: config_file
  end
end
