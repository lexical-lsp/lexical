defmodule Lexical.RemoteControl.Build.State do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.Plugin
  require Logger

  import Messages

  use Build.Progress

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
    build_path = Project.build_path(project)

    unless File.exists?(build_path) do
      File.mkdir_p!(build_path)
    end
  end

  def compile_project(%__MODULE__{} = state, force?) do
    state = increment_build_number(state)
    project = state.project

    Build.with_lock(fn ->
      compile_requested_message =
        project_compile_requested(project: project, build_number: state.build_number)

      RemoteControl.notify_listener(compile_requested_message)
      {elapsed_us, result} = :timer.tc(fn -> safe_compile_project(project, force?) end)
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

      RemoteControl.notify_listener(compile_message)
      RemoteControl.notify_listener(diagnostics_message)
      CodeIntelligence.Structs.discover_deps_structs()
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
      RemoteControl.notify_listener(file_compile_requested(uri: document.uri))

      safe_compile_func = fn ->
        RemoteControl.Mix.in_project(fn _ -> Build.File.compile(document) end)
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

      RemoteControl.notify_listener(compile_message)
      RemoteControl.notify_listener(diagnostics)
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

  def mix_compile_opts(force?) do
    opts = ~w(
        --return-errors
        --ignore-module-conflict
        --all-warnings
        --docs
        --debug-info
        --no-protocol-consolidation
    )

    if force? do
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

  defp safe_compile_project(%Project{} = project, force?) do
    RemoteControl.Mix.in_project(fn _ ->
      Mix.Task.clear()

      prepare_for_project_build(force?)

      compile_fun = fn ->
        Mix.Task.clear()

        with_progress building_label(project), fn ->
          Mix.Task.run(:loadconfig)
          result = Mix.Task.run(:compile, mix_compile_opts(force?))
          Mix.Task.run(:loadpaths)
          result
        end
      end

      case compile_fun.() do
        {:error, diagnostics} ->
          diagnostics =
            diagnostics
            |> List.wrap()
            |> Build.Error.refine_diagnostics()

          {:error, diagnostics}

        {status, diagnostics} when status in [:ok, :noop] ->
          Logger.info(
            "Compile completed with status #{status} " <>
              "Produced #{length(diagnostics)} diagnostics " <>
              inspect(diagnostics)
          )

          Build.Error.refine_diagnostics(diagnostics)
      end
    end)
  end

  defp prepare_for_project_build(false = _force?) do
    :ok
  end

  defp prepare_for_project_build(true = _force?) do
    if connected_to_internet?() do
      with_progress "mix local.hex", fn ->
        Mix.Task.run("local.hex", ~w(--force --if-missing))
      end

      with_progress "mix local.rebar", fn ->
        Mix.Task.run("local.rebar", ~w(--force --if-missing))
      end

      with_progress "mix deps.get", fn ->
        Mix.Task.run("deps.get")
      end
    else
      Logger.warning("Could not connect to hex.pm, dependencies will not be fetched")
    end

    with_progress "mix deps.compile", fn ->
      deps_compile =
        if Version.match?(System.version(), "~> 1.15") do
          "deps.compile"
        else
          "deps.safe_compile"
        end

      Mix.Task.run(deps_compile, ~w(--skip-umbrella-children))
    end

    with_progress "loading plugins", fn ->
      Plugin.Discovery.run()
    end

    Mix.Task.run("clean")
  end

  defp connected_to_internet? do
    # While there's no perfect way to check if a computer is connected to the internet,
    # it seems reasonable to gate pulling dependenices on a resolution check for hex.pm.
    # Yes, it's entirely possible that the DNS server is local, and that the entry is in cache,
    # but that's an edge case, and the build will just time out anyways.
    case :inet_res.getbyname(~c"hex.pm", :a, 250) do
      {:ok, _} -> true
      _ -> false
    end
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
end
