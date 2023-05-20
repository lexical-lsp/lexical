defmodule Lexical.Server.Project.Diagnostics do
  defmodule State do
    alias Lexical.Document
    alias Lexical.Project
    alias Mix.Task.Compiler

    defstruct [:project, :diagnostics_by_uri]

    require Logger

    def new(%Project{} = project) do
      %__MODULE__{project: project, diagnostics_by_uri: %{}}
    end

    def get(%__MODULE__{} = state, source_uri) do
      Map.get(state.diagnostics_by_uri, source_uri, [])
    end

    def clear(%__MODULE__{} = state, source_uri, new_from) do
      diagnostics_by_uri =
        Map.update(state.diagnostics_by_uri, source_uri, [], fn diagnostics ->
          Enum.reject(diagnostics, fn {from, _diagnostic} -> from == new_from end)
        end)

      %__MODULE__{state | diagnostics_by_uri: diagnostics_by_uri}
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

    @default_from "Mix"

    def add(%__MODULE__{} = state, %Compiler.Diagnostic{} = diagnostic, @default_from) do
      source_uri = Document.Path.to_uri(diagnostic.file)

      diagnostics_by_uri =
        Map.update(
          state.diagnostics_by_uri,
          source_uri,
          [{@default_from, diagnostic}],
          fn diagnostics ->
            [{@default_from, diagnostic} | diagnostics]
          end
        )

      %__MODULE__{state | diagnostics_by_uri: diagnostics_by_uri}
    end

    def add(%__MODULE__{} = state, %Mix.Error{} = error, @default_from) do
      project_uri = state.project.mix_exs_uri

      compiler_diagnostic = %Compiler.Diagnostic{
        file: project_uri,
        message: error.message,
        position: 1,
        severity: :error,
        compiler_name: "Mix"
      }

      file_diagnostics =
        Map.update(
          state.diagnostics_by_uri,
          project_uri,
          [{@default_from, compiler_diagnostic}],
          &[{@default_from, compiler_diagnostic} | &1]
        )

      %__MODULE__{state | diagnostics_by_uri: file_diagnostics}
    end

    def add(%__MODULE__{} = state, other, _) do
      Logger.error("Invalid diagnostic: #{inspect(other)}")
      state
    end

    @plugin "Plugin"

    def add(%__MODULE__{} = state, issues, @plugin, uri) do
      file_diagnostics =
        Map.update(
          state.diagnostics_by_uri,
          uri,
          [{@plugin, issues}],
          fn diagnostics ->
            [{@plugin, issues} | diagnostics]
          end
        )

      %__MODULE__{state | diagnostics_by_uri: file_diagnostics}
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
  alias Mix.Task.Compiler

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
  def handle_info(project_diagnostics(diagnostics: diagnostics, from: from), %State{} = state) do
    state = State.clear_all_flushed(state)

    state =
      Enum.reduce(diagnostics, state, fn diagnostic, state ->
        State.add(state, diagnostic, from)
      end)

    publish_diagnostics(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        file_diagnostics(uri: uri, diagnostics: diagnostics, from: from),
        %State{} = state
      ) do
    state = State.clear(state, uri, from)

    state =
      Enum.reduce(diagnostics, state, fn diagnostic, state ->
        if from == "Plugin" do
          State.add(state, diagnostic, from, uri)
        else
          State.add(state, diagnostic, from)
        end
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
      diagnostics = Enum.map(diagnostic_list, fn {_from, diagnostic} -> diagnostic end)
      notification = PublishDiagnostics.new(uri: uri, diagnostics: diagnostics)

      Transport.write(notification)
    end)
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::diagnostics"
  end
end
