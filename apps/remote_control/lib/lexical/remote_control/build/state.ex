defmodule Lexical.RemoteControl.Build.State do
  alias Elixir.Features
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Plugin
  alias Lexical.VM.Versions

  require Logger

  import Messages

  use RemoteControl.Progress

  defstruct project: nil, build_number: 0, uri_to_source_and_edit_time: %{}

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def on_tick(%__MODULE__{} = state) do
    {new_state, compiled_uris} =
      Enum.reduce(state.uri_to_source_and_edit_time, {state, []}, fn
        {uri, {document, edit_time}}, {state, compiled_uris} ->
          if should_compile?(edit_time) do
            new_state = increment_build_number(state)
            compile_file(new_state, document)
            {new_state, [uri | compiled_uris]}
          else
            {state, compiled_uris}
          end
      end)

    %__MODULE__{
      new_state
      | uri_to_source_and_edit_time: Map.drop(state.uri_to_source_and_edit_time, compiled_uris)
    }
  end

  def compile_scheduled?(%__MODULE__{} = state, uri) do
    Map.has_key?(state.uri_to_source_and_edit_time, uri)
  end

  def ensure_build_directory(%__MODULE__{} = state) do
    # If the project directory isn't there, for some reason the main build fails, so we create it here
    # to ensure that the build will succeed.
    project = state.project
    build_path = RemoteControl.Build.path(project)

    unless Versions.compatible?(build_path) do
      Logger.info("Build path #{build_path} was compiled on a previous erlang version. Deleting")

      if File.exists?(build_path) do
        File.rm_rf(build_path)
      end
    end

    maybe_delete_old_builds(project)

    unless File.exists?(build_path) do
      File.mkdir_p!(build_path)
      Versions.write(build_path)
    end
  end

  def compile_project(%__MODULE__{} = state, initial?) do
    state = increment_build_number(state)
    project = state.project

    Build.with_lock(fn ->
      compile_requested_message =
        project_compile_requested(project: project, build_number: state.build_number)

      RemoteControl.broadcast(compile_requested_message)
      {elapsed_us, result} = :timer.tc(fn -> Build.Project.compile(project, initial?) end)
      elapsed_ms = to_ms(elapsed_us)

      {compile_message, diagnostics} =
        case result do
          :ok ->
            message = project_compiled(status: :success, project: project, elapsed_ms: elapsed_ms)

            {message, []}

          {:ok, diagnostics} ->
            message = project_compiled(status: :success, project: project, elapsed_ms: elapsed_ms)

            {message, List.wrap(diagnostics)}

          {:error, diagnostics} ->
            message = project_compiled(status: :error, project: project, elapsed_ms: elapsed_ms)

            {message, List.wrap(diagnostics)}
        end

      diagnostics_message =
        project_diagnostics(
          project: project,
          build_number: state.build_number,
          diagnostics: diagnostics
        )

      RemoteControl.broadcast(compile_message)
      RemoteControl.broadcast(diagnostics_message)
      Plugin.diagnose(project, state.build_number)
    end)
  end

  def on_file_compile(%__MODULE__{} = state, %Document{} = document) do
    %__MODULE__{
      state
      | uri_to_source_and_edit_time:
          Map.put(state.uri_to_source_and_edit_time, document.uri, {document, now()})
    }
  end

  def compile_file(%__MODULE__{} = state, %Document{} = document) do
    project = state.project

    Build.with_lock(fn ->
      RemoteControl.broadcast(file_compile_requested(uri: document.uri))

      safe_compile_func = fn ->
        RemoteControl.Mix.in_project(fn _ -> Build.Document.compile(document) end)
      end

      {elapsed_us, result} = :timer.tc(fn -> safe_compile_func.() end)

      elapsed_ms = to_ms(elapsed_us)

      {compile_message, diagnostics} =
        case result do
          {:ok, diagnostics} ->
            message =
              file_compiled(
                project: project,
                build_number: state.build_number,
                status: :success,
                uri: document.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}

          {:error, diagnostics} ->
            message =
              file_compiled(
                project: project,
                build_number: state.build_number,
                status: :error,
                uri: document.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}
        end

      diagnostics =
        file_diagnostics(
          project: project,
          build_number: state.build_number,
          uri: document.uri,
          diagnostics: List.wrap(diagnostics)
        )

      RemoteControl.broadcast(compile_message)
      RemoteControl.broadcast(diagnostics)
      Plugin.diagnose(project, state.build_number, document)
    end)
  end

  def set_compiler_options do
    Code.compiler_options(
      parser_options: parser_options(),
      tracers: [RemoteControl.Compilation.Tracer]
    )

    :ok
  end

  def mix_compile_opts(initial?) do
    opts = ~w(
        --return-errors
        --ignore-module-conflict
        --all-warnings
        --docs
        --debug-info
        --no-protocol-consolidation
    )

    if initial? do
      ["--force " | opts]
    else
      opts
    end
  end

  def building_label(%Project{} = project) do
    "Building #{Project.display_name(project)}"
  end

  defp now do
    System.system_time(:millisecond)
  end

  defp should_compile?(last_edit_time) do
    millis_since_last_edit = now() - last_edit_time
    millis_since_last_edit >= edit_window_millis()
  end

  defp to_ms(microseconds) do
    microseconds / 1000
  end

  defp parser_options do
    [columns: true, token_metadata: true]
  end

  defp edit_window_millis do
    Application.get_env(:remote_control, :edit_window_millis, 250)
  end

  defp increment_build_number(%__MODULE__{} = state) do
    %__MODULE__{state | build_number: state.build_number + 1}
  end

  @two_month_seconds 86_400 * 31 * 2
  defp maybe_delete_old_builds(%Project{} = project) do
    build_root = Project.build_path(project)
    two_months_ago = System.system_time(:second) - @two_month_seconds

    case File.ls(build_root) do
      {:ok, entries} ->
        for file_name <- entries,
            absolute_path = Path.join(build_root, file_name),
            File.dir?(absolute_path),
            newest_beam_mtime(absolute_path) <=
              two_months_ago do
          File.rm_rf!(absolute_path)
        end

      _ ->
        :ok
    end
  end

  defp newest_beam_mtime(directory) do
    directory
    |> Path.join("**/*.beam")
    |> Path.wildcard()
    |> then(fn
      [] ->
        0

      beam_files ->
        beam_files
        |> Enum.map(&File.stat!(&1, time: :posix).mtime)
        |> Enum.max()
    end)
  end
end
