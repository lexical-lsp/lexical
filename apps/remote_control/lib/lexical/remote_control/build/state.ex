defmodule Lexical.RemoteControl.Build.State do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeIntelligence
  alias Lexical.RemoteControl.ModuleMappings
  alias Lexical.RemoteControl.Plugin

  require Logger

  import Build.CaptureIO
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

      {elapsed_us, result} = :timer.tc(fn -> safe_compile(document) end)

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
            |> Enum.map(&normalize_and_format/1)

          {:error, diagnostics}

        {status, diagnostics} when status in [:ok, :noop] ->
          Logger.info(
            "Compile completed with status #{status} " <>
              "Produced #{length(diagnostics)} diagnostics " <>
              inspect(diagnostics)
          )

          Enum.map(diagnostics, &normalize_and_format/1)
      end
    end)
  end

  defp normalize_and_format(error) do
    error
    |> Build.Error.normalize_diagnostic()
    |> Build.Error.format()
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
      deps_compile = if System.version() >= "1.15", do: "deps.compile", else: "deps.safe_compile"
      Mix.Task.run(deps_compile, ~w(--skip-umbrella-children))
    end

    with_progress "loading plugins", fn ->
      Plugin.Discovery.run()
    end

    Mix.Task.run("clean")
  end

  defp safe_compile(%Document{} = document) do
    old_modules = ModuleMappings.modules_in_file(document.path)

    compile_code_func =
      if System.version() >= "1.15" do
        &compile_code_after_1_15/1
      else
        &compile_code/1
      end

    compile_func = fn document ->
      case RemoteControl.Mix.in_project(fn _ -> compile_code_func.(document) end) do
        {:ok, result} -> result
        other -> other
      end
    end

    if System.version() >= "1.15" do
      do_compile(compile_func, document, old_modules)
    else
      capture_compile_io(compile_func, document, old_modules)
    end
  end

  defp do_compile(compile_func, document, old_modules) do
    case compile_func.(document) do
      {{:ok, modules}, []} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {{:ok, modules}, all_errors_and_warnings} ->
        purge_removed_modules(old_modules, modules)

        diagnostics =
          document
          |> Build.Error.diagnostics_from_mix(all_errors_and_warnings)
          |> Build.Error.uniq()
          |> Enum.map(&Build.Error.format/1)

        {:ok, diagnostics}

      {:error, {meta, message_info, token}} ->
        errors = Build.Error.parse_error_to_diagnostics(document, meta, message_info, token)
        {:error, errors}

      {{:exception, exception, stack, quoted_ast}, all_errors_and_warnings} ->
        converted = Build.Error.error_to_diagnostic(document, exception, stack, quoted_ast)
        maybe_diagnostics = Build.Error.diagnostics_from_mix(document, all_errors_and_warnings)

        diagnostics =
          [converted | maybe_diagnostics]
          |> Enum.reverse()
          |> Build.Error.uniq()
          |> Enum.map(&Build.Error.format/1)

        {:error, diagnostics}
    end
  end

  defp capture_compile_io(compile_func, document, old_modules) do
    compile = fn -> compile_func.(document) end

    case capture_io(:stderr, compile) do
      {captured_messages, {:error, {:exception, {exception, _inner_stack}, stack}}} ->
        error = Build.Error.error_to_diagnostic(document, exception, stack, [])
        diagnostics = Build.Error.message_to_diagnostic(document, captured_messages)

        {:error, [error | diagnostics]}

      {captured_messages, {:error, {meta, message_info, token}}} ->
        errors = Build.Error.parse_error_to_diagnostics(document, meta, message_info, token)
        diagnostics = Build.Error.message_to_diagnostic(document, captured_messages)

        {:error, errors ++ diagnostics}

      {captured_messages, {:exception, exception, stack, quoted_ast}} ->
        error = Build.Error.error_to_diagnostic(document, exception, stack, quoted_ast)
        diagnostics = Build.Error.message_to_diagnostic(document, captured_messages)

        {:error, [error | diagnostics]}

      {"", modules} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {captured_warnings, modules} ->
        purge_removed_modules(old_modules, modules)

        diagnostics = Build.Error.message_to_diagnostic(document, captured_warnings)

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

        Mix.Task.run(:loadconfig)
        Code.compile_quoted(quoted_ast, document.path)
      rescue
        exception ->
          {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
          {:exception, filled_exception, stack, quoted_ast}
      end
    end
  end

  @dialyzer {:nowarn_function, compile_code_after_1_15: 1}

  defp compile_code_after_1_15(%Document{} = document) do
    source_string = Document.to_string(document)
    parser_options = [file: document.path] ++ parser_options()
    Code.put_compiler_option(:ignore_module_conflict, true)

    with {:ok, quoted_ast} <- Code.string_to_quoted(source_string, parser_options) do
      Code.with_diagnostics(fn ->
        try do
          if Path.basename(document.path) == "mix.exs" do
            Mix.ProjectStack.pop()
          end

          Mix.Task.run(:loadconfig)

          modules = Code.compile_quoted(quoted_ast, document.path)
          Code.put_compiler_option(:ignore_module_conflict, false)

          {:ok, modules}
        rescue
          exception ->
            {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
            {:exception, filled_exception, stack, quoted_ast}
        end
      end)
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
