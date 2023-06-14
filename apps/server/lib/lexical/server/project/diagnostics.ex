defmodule Lexical.Server.Project.Diagnostics do
  alias Lexical.Formats
  alias Lexical.Project
  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server.Project.Diagnostics.State
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Transport

  import Messages
  require Logger
  use GenServer

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  # GenServer callbacks

  @impl GenServer
  def init([%Project{} = project]) do
    Dispatch.register(project, [
      file_diagnostics(),
      project_compile_requested(),
      project_compiled(),
      project_diagnostics()
    ])

    state = State.new(project)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(project_compile_requested(), %State{} = state) do
    state = State.clear_all_flushed(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        project_diagnostics(build_number: build_number, diagnostics: diagnostics),
        %State{} = state
      ) do
    state =
      Enum.reduce(diagnostics, state, fn diagnostic, state ->
        State.add(state, build_number, diagnostic)
      end)

    publish_diagnostics(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        file_diagnostics(uri: uri, build_number: build_number, diagnostics: diagnostics),
        %State{} = state
      ) do
    state =
      case diagnostics do
        [] ->
          State.clear(state, uri)

        diagnostics ->
          Enum.reduce(diagnostics, state, fn diagnostic, state ->
            State.add(state, build_number, diagnostic)
          end)
      end

    publish_diagnostics(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        project_compiled(elapsed_ms: elapsed_ms),
        %State{} = state
      ) do
    project_name = Project.name(state.project)
    Logger.info("Compiled #{project_name} in #{Formats.time(elapsed_ms, unit: :millisecond)}")

    {:noreply, state}
  end

  # Private

  defp publish_diagnostics(%State{} = state) do
    Enum.each(state.entries_by_uri, fn {uri, %State.Entry{} = entry} ->
      diagnostics_list = State.Entry.diagnostics(entry)
      notification = PublishDiagnostics.new(uri: uri, diagnostics: diagnostics_list)

      Transport.write(notification)
    end)
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::diagnostics"
  end
end
