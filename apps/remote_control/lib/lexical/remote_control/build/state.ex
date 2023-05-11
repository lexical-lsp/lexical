defmodule Lexical.RemoteControl.Build.State do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.ModuleMappings

  require Logger

  import Build.CaptureIO
  import Messages

  use Build.Progress

  defstruct project: nil, uri_to_source_and_edit_time: %{}

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def on_tick(%__MODULE__{} = state) do
    compiled_uris =
      for {uri, {document, edit_time}} <- state.uri_to_source_and_edit_time,
          should_compile?(edit_time) do
        Logger.debug("On-type compiling #{document.path}")
        compile_file(state.project, document)
        uri
      end

    %__MODULE__{
      state
      | uri_to_source_and_edit_time: Map.drop(state.uri_to_source_and_edit_time, compiled_uris)
    }
  end

  def compile_scheduled?(%__MODULE__{} = state, uri) do
    Map.has_key?(state.uri_to_source_and_edit_time, uri)
  end

  def initial_compile(%__MODULE__{} = state) do
    # If the project directory isn't there, for some reason the main build fails, but a
    # non-forced build will work, after which the project can be built correctly.
    project = state.project

    unless File.exists?(Project.build_path(project)) do
      Logger.info("Performing initial build on new workspace")

      result =
        RemoteControl.Mix.in_project(project, fn _ ->
          with_progress "compile", fn ->
            Mix.Task.run(:compile, mix_compile_opts(false))
          end
        end)

      case result do
        {:error, {:exception, ex}} ->
          Logger.error("Initial compile failed #{Exception.message(ex)}")

        _ ->
          Logger.info("initial build complete")
      end
    end

    update_build_path(project)
  end

  def compile_project(%__MODULE__{} = state, force?) do
    project = state.project

    Build.with_lock(fn ->
      {elapsed_us, result} = :timer.tc(fn -> safe_compile_project(force?) end)
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

      diagnostics_message = project_diagnostics(project: project, diagnostics: diagnostics)

      RemoteControl.notify_listener(compile_message)
      RemoteControl.notify_listener(diagnostics_message)
    end)
  end

  def on_file_compile(%__MODULE__{} = state, %Document{} = document) do
    %__MODULE__{
      state
      | uri_to_source_and_edit_time:
          Map.put(state.uri_to_source_and_edit_time, document.uri, {document, now()})
    }
  end

  def compile_file(%Project{} = project, %Document{} = document) do
    Build.with_lock(fn ->
      RemoteControl.notify_listener(file_compile_requested(uri: document.uri))

      {elapsed_us, result} = :timer.tc(fn -> safe_compile(document) end)

      elapsed_ms = to_ms(elapsed_us)

      {compile_message, diagnostics} =
        case result do
          {:ok, diagnostics} ->
            message =
              file_compiled(
                status: :success,
                project: project,
                uri: document.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}

          {:error, diagnostics} ->
            message =
              file_compiled(
                status: :error,
                project: project,
                uri: document.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}
        end

      diagnostics =
        file_diagnostics(
          project: project,
          uri: document.uri,
          diagnostics: List.wrap(diagnostics)
        )

      RemoteControl.notify_listener(compile_message)
      RemoteControl.notify_listener(diagnostics)
    end)
  end

  def set_compiler_options do
    Code.compiler_options(
      parser_options: parser_options(),
      tracers: [RemoteControl.CompileTracer]
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

  defp now do
    System.system_time(:millisecond)
  end

  defp should_compile?(last_edit_time) do
    millis_since_last_edit = now() - last_edit_time
    millis_since_last_edit >= edit_window_millis()
  end

  defp safe_compile_project(force?) do
    RemoteControl.Mix.in_project(fn _ ->
      Mix.Task.clear()

      prepare_for_project_build(force?)

      compile_fun = fn ->
        Mix.Task.clear()

        with_progress "compile", fn ->
          Mix.Task.run("compile", mix_compile_opts(force?))
        end
      end

      case compile_fun.() do
        {:error, _} = error ->
          error

        {status, diagnostics} when status in [:ok, :noop] ->
          Logger.info(
            "Compile completed with status #{status} " <>
              "Produced #{length(diagnostics)} diagnostics " <>
              inspect(diagnostics)
          )

          Enum.map(diagnostics, &Build.Error.normalize_diagnostic/1)
      end
    end)
  end

  defp prepare_for_project_build(false = _force?) do
    :ok
  end

  defp prepare_for_project_build(true = _force?) do
    if connected_to_internet?() do
      with_progress "local.hex", fn ->
        Mix.Task.run("local.hex", ~w(--force --if-missing))
      end

      with_progress "local.rebar", fn ->
        Mix.Task.run("local.rebar", ~w(--force --if-missing))
      end

      with_progress "deps.get", fn ->
        Mix.Task.run("deps.get")
      end
    else
      Logger.warn("Could not connect to hex.pm, dependencies will not be fetched")
    end

    with_progress "deps.compile", fn ->
      Mix.Task.run("deps.safe_compile", ~w(--skip-umbrella-children))
    end

    Mix.Task.run("clean")
  end

  defp safe_compile(%Document{} = document) do
    old_modules = ModuleMappings.modules_in_file(document.path)

    compile = fn ->
      case RemoteControl.Mix.in_project(fn _ -> compile_code(document) end) do
        {:ok, result} -> result
        other -> other
      end
    end

    case capture_io(:stderr, compile) do
      {captured_messages, {:error, {meta, message_info, token}}} ->
        errors = Build.Error.parse_error_to_diagnostics(meta, message_info, token)
        diagnostics = Build.Error.message_to_diagnostic(captured_messages)
        diagnostics = ensure_file(errors ++ diagnostics, document)

        {:error, diagnostics}

      {captured_messages, {:exception, exception, stack, quoted_ast}} ->
        error = Build.Error.error_to_diagnostic(exception, stack, quoted_ast)
        diagnostics = Build.Error.message_to_diagnostic(captured_messages)
        diagnostics = ensure_file([error | diagnostics], document)

        {:error, diagnostics}

      {"", modules} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {captured_warnings, modules} ->
        purge_removed_modules(old_modules, modules)

        diagnostics =
          captured_warnings
          |> Build.Error.message_to_diagnostic()
          |> ensure_file(document)

        {:ok, diagnostics}
    end
  end

  defp compile_code(%Document{} = document) do
    source_string = Document.to_string(document)
    parser_options = [file: document.path] ++ parser_options()

    with {:ok, quoted_ast} <- Code.string_to_quoted(source_string, parser_options) do
      try do
        # If we're compiling a mix.exs file, the after compile callback from
        # `use Mix.Project` will blow up if we add the same project to the project stack
        # twice. Preemptively popping it prevents that error from occurring.
        if Path.basename(document.path) == "mix.exs" do
          Mix.ProjectStack.pop()
        end

        Code.compile_quoted(quoted_ast, document.path)
      rescue
        exception ->
          {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
          {:exception, filled_exception, stack, quoted_ast}
      end
    end
  end

  defp purge_removed_modules(old_modules, new_modules) do
    new_modules = MapSet.new(new_modules, fn {module, _bytecode} -> module end)
    old_modules = MapSet.new(old_modules)

    old_modules
    |> MapSet.difference(new_modules)
    |> Enum.each(fn to_remove ->
      :code.purge(to_remove)
      :code.delete(to_remove)
    end)
  end

  defp connected_to_internet? do
    # While there's no perfect way to check if a computer is connected to the internet,
    # it seems reasonable to gate pulling dependenices on a resolution check for hex.pm.
    # Yes, it's entirely possible that the DNS server is local, and that the entry is in cache,
    # but that's an edge case, and the build will just time out anyways.
    case :inet_res.getbyname('hex.pm', :a, 250) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp ensure_file(diagnostics, %Document{} = document) do
    Enum.map(diagnostics, &Map.put(&1, :file, document.path))
  end

  defp to_ms(microseconds) do
    microseconds / 1000
  end

  defp parser_options do
    [columns: true, token_metadata: true]
  end

  defp update_build_path(%Project{} = project) do
    RemoteControl.Mix.in_project(project, fn _ ->
      [Mix.Project.build_path(), "lib", "**", "ebin"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.each(&Code.prepend_path/1)
    end)
  end

  defp edit_window_millis do
    Application.get_env(:remote_control, :edit_window_millis, 250)
  end
end
