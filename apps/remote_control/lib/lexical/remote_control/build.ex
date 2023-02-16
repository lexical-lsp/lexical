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
    RemoteControl.call(project, GenServer, :cast, [__MODULE__, {:compile_file, source_file}])
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
    {elapsed_us, result} = :timer.tc(fn -> safe_compile_project(force?) end)
    elapsed_ms = to_ms(elapsed_us)

    message =
      case result do
        :ok ->
          project_compiled(status: :success, project: project, elapsed_ms: elapsed_ms)

        {:ok, diagnostics} ->
          project_compiled(
            status: :success,
            project: project,
            elapsed_ms: elapsed_ms,
            diagnostics: List.wrap(diagnostics)
          )

        {:error, diagnostics} ->
          project_compiled(
            status: :error,
            project: project,
            elapsed_ms: elapsed_ms,
            diagnostics: List.wrap(diagnostics)
          )
      end

    RemoteControl.notify_listener(message)
    {:noreply, project}
  end

  def handle_cast({:compile_file, %SourceFile{} = source_file}, %Project{} = project) do
    RemoteControl.notify_listener(file_compile_requested(uri: source_file.uri))
    {elapsed_us, result} = :timer.tc(fn -> safe_compile(source_file) end)
    elapsed_ms = to_ms(elapsed_us)

    message =
      case result do
        {:ok, []} ->
          file_compiled(
            status: :success,
            project: project,
            source_file: source_file,
            elapsed_ms: elapsed_ms
          )

        {:ok, diagnostics} ->
          file_compiled(
            status: :success,
            project: project,
            source_file: source_file,
            elapsed_ms: elapsed_ms,
            diagnostics: List.wrap(diagnostics)
          )

        {:error, diagnostics} ->
          file_compiled(
            status: :error,
            project: project,
            source_file: source_file,
            elapsed_ms: elapsed_ms,
            diagnostics: List.wrap(diagnostics)
          )
      end

    RemoteControl.notify_listener(message)

    {:noreply, project}
  end

  def handle_info(_, %Project{} = project) do
    {:noreply, project}
  end

  # Private
  defp set_compiler_options do
    Code.compiler_options(
      parser_options: parser_options(),
      tracers: [RemoteControl.CompileTracer],
      warnings_as_errors: true
    )

    :ok
  end

  defp parser_options do
    [columns: true, token_metadata: true]
  end

  def safe_compile_project(force?) do
    opts = ~w(--return-errors --ignore-module-conflict --all-warnings --docs --debug-info)

    opts =
      if force? do
        ["--force " | opts]
      else
        opts
      end

    RemoteControl.in_mix_project(fn _ ->
      try do
        Mix.Task.clear()
        Mix.Task.run("local.hex", ["--force"])
        Mix.Task.run("local.rebar", ["--force"])
        Mix.Task.run("deps.get")
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
            {:ok, diagnostics}
        end
      rescue
        e ->
          {:error, e}
      end
    end)
  end

  def safe_compile(%SourceFile{} = source_file) do
    compile = fn ->
      result =
        source_file
        |> SourceFile.to_string()
        |> Code.eval_string([], file: source_file.path)

      case result do
        {{:module, module_name, _, _}, _} ->
          module_name
          |> CompileTracer.extract_module_updated()
          |> RemoteControl.notify_listener()

        _ ->
          :ok
      end

      result
    end

    case capture_io(:stderr, compile) do
      {captured_messages, {type, e}} when type in [:error, :exception] ->
        diagnostics = Build.Error.message_to_diagnostic(captured_messages)
        error = Build.Error.error_to_diagnostic(e)
        {:error, [error | diagnostics]}

      {"", _} ->
        {:ok, []}

      {captured_warnings, _} ->
        diagnostics = Build.Error.message_to_diagnostic(captured_warnings)
        {:ok, diagnostics}
    end
  end

  defp to_ms(microseconds) do
    microseconds / 1000
  end
end
