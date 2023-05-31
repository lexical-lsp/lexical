defmodule Lexical.Server.Project.Diagnostics do
  defmodule State do
    alias Lexical.Document
    alias Lexical.Plugin.Diagnostic
    alias Lexical.Project

    defstruct [:project, :diagnostics_by_uri]

    require Logger

    def new(%Project{} = project) do
      %__MODULE__{project: project, diagnostics_by_uri: %{}}
    end

    def get(%__MODULE__{} = state, source_uri) do
      Map.get(state.diagnostics_by_uri, source_uri, [])
    end

    def clear(%__MODULE__{} = state, source_uri) do
      %__MODULE__{state | diagnostics_by_uri: Map.put(state.diagnostics_by_uri, source_uri, [])}
    end

    @doc """
    Only clear diagnostics if they've been synced to disk
    It's possible that the diagnostic presented by typing is still correct, and the file
    that exists on the disk is actually an older copy of the file in memory.
    """
    def clear_all_flushed(%__MODULE__{} = state) do
      cleared =
        Map.new(state.diagnostics_by_uri, fn {uri, diagnostics} ->
          with true <- Document.Store.open?(uri),
               {:ok, %Document{} = document} <- Document.Store.fetch(uri),
               true <- keep_diagnostics?(document) do
            {uri, diagnostics}
          else
            _ ->
              {uri, []}
          end
        end)

      %__MODULE__{state | diagnostics_by_uri: cleared}
    end

    def add(%__MODULE__{} = state, %Diagnostic.Result{} = diagnostic) do
      diagnostics_by_uri =
        Map.update(state.diagnostics_by_uri, diagnostic.uri, [diagnostic], fn diagnostics ->
          [diagnostic | diagnostics]
        end)

      %__MODULE__{state | diagnostics_by_uri: diagnostics_by_uri}
    end

    def add(%__MODULE__{} = state, other) do
      Logger.error("Invalid diagnostic: #{inspect(other)}")
      state
    end

    defp keep_diagnostics?(%Document{} = document) do
      # Keep any diagnostics for script files, which aren't compiled)
      # or dirty files, which have been modified after compilation has occurrend
      document.dirty? or script_file?(document)
    end

    defp script_file?(document) do
      Path.extname(document.path) == ".exs"
    end
  end

  alias Lexical.Document
  alias Lexical.Formats
  alias Lexical.Project
  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.RemoteControl.Api.Messages
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
    Dispatch.register(project, [project_compiled(), file_diagnostics(), project_diagnostics()])

    state = State.new(project)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(project_diagnostics(diagnostics: diagnostics), %State{} = state) do
    state = State.clear_all_flushed(state)

    state =
      Enum.reduce(diagnostics, state, fn diagnostic, state ->
        State.add(state, diagnostic)
      end)

    publish_diagnostics(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(file_diagnostics(uri: uri, diagnostics: diagnostics), %State{} = state) do
    state = State.clear(state, uri)

    state =
      Enum.reduce(diagnostics, state, fn diagnostic, state ->
        State.add(state, diagnostic)
      end)

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
    Enum.each(state.diagnostics_by_uri, fn {uri, diagnostic_list} ->
      notification = PublishDiagnostics.new(uri: uri, diagnostics: diagnostic_list)

      Transport.write(notification)
    end)
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::diagnostics"
  end
end
