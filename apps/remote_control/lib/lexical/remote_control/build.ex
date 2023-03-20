defmodule Lexical.RemoteControl.Build do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CompileTracer
  alias Lexical.SourceFile

  require Logger
  use GenServer

  import Messages
  import Build.CaptureIO

  # Public interface

  def schedule_compile(%Project{} = project, force? \\ false) do
    RemoteControl.call(project, GenServer, :cast, [__MODULE__, {:compile, force?}])
  end

  def compile_source_file(%Project{} = project, %SourceFile{} = source_file) do
    # Don't format mix.exs files until we come up with with a way to prevent them from causing errors
    unless Path.absname(source_file.path) == "mix.exs" do
      RemoteControl.call(project, GenServer, :cast, [__MODULE__, {:compile_file, source_file}])
    end

    :ok
  end

  def with_lock(func) do
    RemoteControl.with_lock(__MODULE__, func)
  end

  # GenServer Callbacks
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    project = RemoteControl.get_project()

    with :ok <- set_compiler_options() do
      {:ok, project}
    end
  end

  def handle_cast({:compile, force?}, %Project{} = project) do
    with_lock(fn ->
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
      {:noreply, project}
    end)
  end

  def handle_cast({:compile_file, %SourceFile{} = source_file}, %Project{} = project) do
    with_lock(fn ->
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

      :logger.info("Emitting #{inspect(diagnostics)}")

      diagnostics =
        file_diagnostics(
          project: project,
          uri: source_file.uri,
          diagnostics: List.wrap(diagnostics)
        )

      RemoteControl.notify_listener(compile_message)
      RemoteControl.notify_listener(diagnostics)

      {:noreply, project}
    end)
  end

  def handle_info(_, %Project{} = project) do
    {:noreply, project}
  end

  # Private
  defp set_compiler_options do
    Code.compiler_options(
      parser_options: parser_options(),
      tracers: [RemoteControl.CompileTracer]
    )

    :ok
  end

  defp parser_options do
    [columns: true, token_metadata: true]
  end

  defp safe_compile_project(force?) do
    opts = ~w(
        --return-errors
        --ignore-module-conflict
        --all-warnings
        --docs
        --debug-info
        --no-protocol-consolidation
    )

    opts =
      if force? do
        ["--force " | opts]
      else
        opts
      end

    RemoteControl.in_mix_project(fn _ ->
      try do
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
          capture_io(:stderr, fn -> Mix.Task.run("compile", opts) end)
        end

        case compile_fun.() do
          {_output, {:error, _} = error} ->
            error

          {_output, {_status, []}} ->
            {:ok, []}

          {_output, {status, [_ | _] = diagnostics}} when status in [:ok, :noop] ->
            {:ok, Enum.map(diagnostics, &Build.Error.normalize_diagnostic/1)}
        end
      rescue
        e ->
          {:error, e}
      end
    end)
  end

  defp safe_compile(%SourceFile{} = source_file) do
    source_string = SourceFile.to_string(source_file)
    parser_options = [file: source_file.path] ++ parser_options()

    compile = fn ->
      with {:ok, quoted_ast} <- Code.string_to_quoted(source_string, parser_options) do
        try do
          Code.compile_quoted(quoted_ast, source_file.path)
        rescue
          exception ->
            {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
            {:exception, filled_exception, stack, quoted_ast}
        end
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
        maybe_purge(modules)
        {:ok, []}

      {captured_warnings, modules} ->
        maybe_purge(modules)

        diagnostics =
          captured_warnings
          |> Build.Error.message_to_diagnostic()
          |> ensure_file(source_file)

        {:ok, diagnostics}
    end
  end

  defp ensure_file(diagnostics, %SourceFile{} = source_file) do
    Enum.map(diagnostics, &Map.put(&1, :file, source_file.path))
  end

  defp to_ms(microseconds) do
    microseconds / 1000
  end

  defp maybe_purge(module_list) do
    # When using code snippets to define a module, as the user types the module name,
    # multiple modules are created, as each character is typed. For example, if the
    # snippet's module name is Mod the following modules would be created; [M, Mo, Mod].
    # To prevent this, we'll purge any modules during incremental file compilation that
    # define no functions, macros, structs, or types.

    Enum.each(module_list, fn {module_name, bytecode} ->
      case CompileTracer.extract_module_updated(module_name) do
        module_updated(functions: [], macros: [], struct: nil) ->
          unless has_types?(bytecode) do
            :code.purge(module_name)
            :code.delete(module_name)
          end

        _ ->
          :ok
      end
    end)
  end

  defp has_types?(bytecode) do
    case :beam_lib.chunks(bytecode, [:abstract_code]) do
      {:ok, {_mod_name, terms}} ->
        {:raw_abstract_v1, code} = Keyword.get(terms, :abstract_code)
        Enum.any?(code, &match?({:attribute, _, :type, _}, &1))

      _ ->
        false
    end
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
end
