defmodule Lexical.RemoteControl.Build do
  alias Lexical.RemoteControl.Build
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
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

    with :ok <- set_compiler_options(),
         {:ok, _mix_module} <- load_mix_exs(project),
         {:ok, deps} <- project_deps(),
         :ok <- :code.add_pathsz(deps) do
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
        :ok ->
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

  defp find_mix_exs(%Project{} = project) do
    with path when is_binary(path) <- Project.mix_exs_path(project),
         true <- File.exists?(path) do
      {:ok, path}
    else
      _ ->
        {:error, :no_mix_exs}
    end
  end

  defp load_mix_exs(%Project{} = project) do
    with {:ok, mix_exs_path} <- find_mix_exs(project),
         {:ok, [project_module], _} <- Kernel.ParallelCompiler.compile([mix_exs_path]) do
      {:ok, project_module}
    end
  end

  def project_deps do
    build_root = Path.join(Mix.Project.build_path(), "lib")

    deps_paths =
      for dep_dir <- File.ls!(build_root),
          ebin_path = Path.join([build_root, dep_dir, "ebin"]),
          File.exists?(ebin_path) do
        String.to_charlist(ebin_path)
      end

    {:ok, deps_paths}
  end

  def safe_compile_project(force?) do
    opts = ~w(--return-errors --ignore-module-conflicts --warnings-as-errors)

    opts =
      if force? do
        ["--force " | opts]
      else
        opts
      end

    try do
      Mix.Task.clear()
      Mix.Task.run("local.hex", ["--force"])
      Mix.Task.run("local.rebar", ["--force"])

      if force? do
        Mix.Task.run("clean")
      end

      compile_fun = fn ->
        {result, _ignored_io} =
          capture_io(fn ->
            Mix.Task.run("compile", opts)
          end)

        result
      end

      case compile_fun.() do
        {:error, _} = error ->
          error

        {_, []} ->
          :ok

        {status, [_ | _] = diagnostics} when status in [:ok, :noop] ->
          {:ok, diagnostics}
      end
    rescue
      e ->
        {:error, e}
    end
  end

  defp safe_compile(%SourceFile{} = source_file) do
    try do
      capture_io(:stderr, fn ->
        source_file
        |> SourceFile.to_string()
        |> Code.compile_string(source_file.path)
      end)
    rescue
      e ->
        {:error, [Build.Error.error_to_diagnostic(e)]}
    else
      {_, ""} ->
        :ok

      {_, captured_warnings} ->
        diagnostics = Build.Error.message_to_diagnostic(captured_warnings)
        {:ok, diagnostics}
    end
  end

  defp to_ms(microseconds) do
    microseconds / 1000
  end
end
