defmodule Lexical.RemoteControl.Build.State do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.ModuleMappings
  alias Lexical.SourceFile

  import Build.CaptureIO
  import Messages
  require Logger

  defstruct project: nil, uri_to_source_and_edit_time: %{}

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def on_tick(%__MODULE__{} = state) do
    compiled_uris =
      for {uri, {source_file, edit_time}} <- state.uri_to_source_and_edit_time,
          should_compile?(edit_time) do
        Logger.debug("On-type compiling #{source_file.path}")
        compile_file(state.project, source_file)
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
          Mix.Task.run(:compile, mix_compile_opts(false))
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

  def on_file_compile(%__MODULE__{} = state, %SourceFile{} = source_file) do
    %__MODULE__{
      state
      | uri_to_source_and_edit_time:
          Map.put(state.uri_to_source_and_edit_time, source_file.uri, {source_file, now()})
    }
  end

  def compile_file(%Project{} = project, %SourceFile{} = source_file) do
    Build.with_lock(fn ->
      RemoteControl.notify_listener(file_compile_requested(uri: source_file.uri))

      {elapsed_us, result} = :timer.tc(fn -> safe_compile(source_file) end)

      elapsed_ms = to_ms(elapsed_us)

      {compile_message, diagnostics} =
        case result do
          {:ok, diagnostics} ->
            message =
              file_compiled(
                status: :success,
                project: project,
                uri: source_file.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}

          {:error, diagnostics} ->
            message =
              file_compiled(
                status: :error,
                project: project,
                uri: source_file.uri,
                elapsed_ms: elapsed_ms
              )

            {message, diagnostics}
        end

      diagnostics =
        file_diagnostics(
          project: project,
          uri: source_file.uri,
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

      if connected_to_internet?() do
        Mix.Task.run("local.hex", ~w(--force --if-missing))
        Mix.Task.run("local.rebar", ~w(--force --if-missing))
        Mix.Task.run("deps.get")
      else
        Logger.warn("Could not connect to hex.pm, dependencies will not be fetched")
      end

      Mix.Task.run("deps.safe_compile")

      if force? do
        Mix.Task.run("clean")
      end

      compile_fun = fn ->
        Mix.Task.clear()
        Mix.Task.run("compile", mix_compile_opts(force?))
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

  defp safe_compile(%SourceFile{} = source_file) do
    old_modules = ModuleMappings.modules_in_file(source_file.path)

    compile = fn ->
      case RemoteControl.Mix.in_project(fn _ -> compile_code(source_file) end) do
        {:ok, result} -> result
        other -> other
      end
    end

    case capture_io(:stderr, compile) do
      {captured_messages, {:error, {meta, message_info, token}}} ->
        errors = Build.Error.parse_error_to_diagnostics(meta, message_info, token)
        diagnostics = Build.Error.message_to_diagnostic(captured_messages)
        diagnostics = ensure_file(errors ++ diagnostics, source_file)

        {:error, diagnostics}

      {captured_messages, {:exception, exception, stack, quoted_ast}} ->
        error = Build.Error.error_to_diagnostic(exception, stack, quoted_ast)
        diagnostics = Build.Error.message_to_diagnostic(captured_messages)
        diagnostics = ensure_file([error | diagnostics], source_file)

        {:error, diagnostics}

      {"", modules} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {captured_warnings, modules} ->
        purge_removed_modules(old_modules, modules)

        diagnostics =
          captured_warnings
          |> Build.Error.message_to_diagnostic()
          |> ensure_file(source_file)

        {:ok, diagnostics}
    end
  end

  defp compile_code(%SourceFile{} = source_file) do
    source_string = SourceFile.to_string(source_file)
    parser_options = [file: source_file.path] ++ parser_options()

    with {:ok, quoted_ast} <- Code.string_to_quoted(source_string, parser_options) do
      try do
        # If we're compiling a mix.exs file, the after compile callback from
        # `use Mix.Project` will blow up if we add the same project to the project stack
        # twice. Preemptively popping it prevents that error from occurring.
        if Path.basename(source_file.path) == "mix.exs" do
          Mix.ProjectStack.pop()
        end

        Code.compile_quoted(quoted_ast, source_file.path)
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

  defp ensure_file(diagnostics, %SourceFile{} = source_file) do
    Enum.map(diagnostics, &Map.put(&1, :file, source_file.path))
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
