defmodule Lexical.Server.Project.Diagnostics do
  defmodule State do
    alias Lexical.CodeUnit
    alias Lexical.SourceFile
    alias Lexical.Project
    alias Lexical.Protocol.Types.Diagnostic
    alias Lexical.Protocol.Types.Position
    alias Lexical.Protocol.Types.Range
    alias Mix.Task.Compiler

    defstruct [:project, :diagnostics_by_uri]

    def new(%Project{} = project) do
      %__MODULE__{project: project, diagnostics_by_uri: %{}}
    end

    def get(%__MODULE__{} = state, source_uri) do
      Map.get(state.diagnostics_by_uri, source_uri, [])
    end

    def clear(%__MODULE__{} = state, source_uri) do
      %__MODULE__{state | diagnostics_by_uri: Map.put(state.diagnostics_by_uri, source_uri, [])}
    end

    def clear_all(%__MODULE__{} = state) do
      cleared = Map.new(state.diagnostics_by_uri, fn {k, _} -> {k, []} end)
      %__MODULE__{state | diagnostics_by_uri: cleared}
    end

    def add(
          %__MODULE__{} = state,
          %Compiler.Diagnostic{} = diagnostic,
          %SourceFile{} = source_file
        ) do
      lsp_diagnostic = to_protocol(diagnostic, source_file)

      file_diagnostics =
        Map.update(
          state.diagnostics_by_uri,
          source_file.uri,
          [lsp_diagnostic],
          &[lsp_diagnostic | &1]
        )

      %{state | diagnostics_by_uri: file_diagnostics}
    end

    def add(%__MODULE__{} = state, %Mix.Error{} = error) do
      project_uri = state.project.mix_exs_uri
      lsp_diagnostic = to_protocol(error, project_uri)

      file_diagnostics =
        Map.update(
          state.diagnostics_by_uri,
          project_uri,
          [lsp_diagnostic],
          &[lsp_diagnostic | &1]
        )

      %{state | diagnostics_by_uri: file_diagnostics}
    end

    def add(%__MODULE__{} = state, %Compiler.Diagnostic{} = diagnostic) do
      source_uri = SourceFile.Path.to_uri(diagnostic.file)

      with {:ok, lsp_diagnostic} <- to_protocol(diagnostic, source_uri) do
        diagnostics_by_uri =
          Map.update(state.diagnostics_by_uri, source_uri, [lsp_diagnostic], fn diagnostics ->
            [lsp_diagnostic | diagnostics]
          end)

        %__MODULE__{state | diagnostics_by_uri: diagnostics_by_uri}
      else
        _ ->
          state
      end
    end

    defp to_protocol(%Compiler.Diagnostic{} = diagnostic, %SourceFile{} = source_file) do
      %Diagnostic{
        message: diagnostic.message,
        range: position_to_range(source_file, diagnostic.position),
        severity: diagnostic.severity,
        source: "Elixir"
      }
    end

    defp to_protocol(%Compiler.Diagnostic{} = diagnostic, source_uri)
         when is_binary(source_uri) do
      with {:ok, source_file} <- SourceFile.Store.open_temporary(source_uri) do
        {:ok, to_protocol(diagnostic, source_file)}
      end
    end

    defp to_protocol(%Mix.Error{} = diagnostic, _) do
      %Diagnostic{
        message: diagnostic.message,
        range:
          Range.new(
            start: Position.new(line: 0, character: 0),
            end: Position.new(line: 1, character: 0)
          ),
        severity: :error,
        source: "Mix"
      }
    end

    defp position_to_range(_, line) when is_integer(line) do
      Range.new(
        start: Position.new(line: max(line - 1, 0), character: 0),
        end: Position.new(line: line, character: 0)
      )
    end

    defp position_to_range(%SourceFile{} = source_file, {line_number, column}) do
      with {:ok, line_text} <- SourceFile.fetch_text_at(source_file, line_number),
           {:ok, character} <- CodeUnit.to_utf16(line_text, column) do
        Range.new(
          start: Position.new(line: line_number, character: character),
          end: Position.new(line: line_number, character: character)
        )
      end
    end
  end

  alias Lexical.Protocol.Notifications.PublishDiagnostics
  alias Lexical.Protocol.Types.Diagnostic
  alias Lexical.Project
  alias Lexical.Server.Project.Dispatch
  alias Lexical.SourceFile
  alias Lexical.RemoteControl.Api.Messages
  alias Mix.Task.Compiler

  import Messages
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
    Dispatch.register(project, [project_compiled(), file_compiled()])
    state = State.new(project)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(project_compiled(diagnostics: diagnostics), %State{} = state) do
    uris =
      Enum.map(diagnostics, fn
        %Mix.Error{} ->
          state.project.mix_exs_uri

        %Compiler.Diagnostic{file: file} ->
          SourceFile.Path.to_uri(file)
      end)

    state = Enum.reduce(uris, state, &State.clear(&2, &1))
    state = Enum.reduce(diagnostics, state, &State.add(&2, &1))
    publish_diagnostics(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        file_compiled(diagnostics: diagnostics, source_file: %SourceFile{} = source_file),
        %State{} = state
      ) do
    state = State.clear(state, source_file.uri)
    state = Enum.reduce(diagnostics, state, &State.add(&2, &1, source_file))
    publish_diagnostics(state)
    {:ok, state}
  end

  # Private

  defp publish_diagnostics(%State{} = state) do
    Enum.each(state.diagnostics_by_uri, fn {uri, diagnostic_list} ->
      notification =
        PublishDiagnostics.new(
          uri: uri,
          diagnostics: diagnostic_list
        )

      Lexical.Server.Transport.write(notification)
    end)
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::diagnostics"
  end
end
