defmodule Mix.Tasks.Compile.LibElixir do
  @moduledoc """
  A utility for generating namespaced core Elixir modules for any version.
  """

  use Mix.Task.Compiler

  alias LibElixir.Artifact
  alias LibElixir.Namespace

  require Logger

  @impl true
  def run(_args) do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    :ok = Application.ensure_loaded(app)

    manifest = get_manifest()

    needs_compile =
      Enum.filter(lib_elixirs(), fn {module, ref} ->
        get_in(manifest.libs[module]) != ref
      end)

    if needs_compile == [] do
      :noop
    else
      manifest =
        Enum.reduce(needs_compile, manifest, fn {module, ref}, manifest ->
          clean_lib(module)
          Mix.shell().info("[lib_elixir] Compiling #{inspect(module)} (Elixir #{ref})")
          compile(module, ref)
          put_in(manifest.libs[module], ref)
        end)

      write_manifest(manifest)

      :ok
    end
  end

  @impl true
  def manifests do
    [manifest_path()]
  end

  @impl true
  def clean do
    File.rm(manifest_path())
    :ok
  end

  def compile(module, ref) do
    ez_path = Artifact.ez_path(ref, module)

    if Artifact.exists?(ez_path) do
      extract_ez(ez_path)
    else
      Logger.info("lib_elixir: Building #{inspect(module)} (Elixir #{ref})")
      archive_path = Artifact.download_elixir_archive!(ref)

      with_tmp_dir(fn tmp_dir ->
        Artifact.extract_archive!(archive_path, tmp_dir)

        # The only top-level directory after extracting the archive
        # is the Elixir source directory
        [source_dir] = File.ls!(tmp_dir)
        source_dir = Path.join(tmp_dir, source_dir)

        ebin_path = compile_elixir_stdlib!(source_dir)
        Namespace.apply!(ebin_path, module)

        container_name = ez_path |> Path.basename() |> Path.rootname()
        container_path = Path.join(tmp_dir, container_name)
        container_ebin = Path.join(container_path, "ebin")

        File.mkdir_p!(container_ebin)
        File.cp_r!(ebin_path, container_ebin)
        Artifact.compress_ez!(ez_path, container_path)

        extract_ez(ez_path)
      end)
    end

    :ok
  end

  defp extract_ez(ez_path) do
    ez_name = Path.basename(ez_path)

    target_dir =
      [Mix.Project.build_path(), "lib"]
      |> Path.join()
      |> Path.expand()

    target_ez = Path.join(target_dir, ez_name)

    File.cp!(ez_path, target_ez)
    {:ok, _} = :zip.unzip(~c"#{target_ez}", cwd: ~c"#{target_dir}")

    File.rm!(target_ez)
  end

  defp compile_elixir_stdlib!(source_dir) do
    case System.cmd("make", ["clean", "erlang", "app", "stdlib"], cd: source_dir) do
      {_, 0} ->
        ebin_path = Path.join([source_dir, "lib", "elixir", "ebin"])

        # Remove `lib_iex.beam`; we don't want it.
        ebin_path |> Path.join("*iex.beam") |> Path.wildcard() |> Enum.each(&File.rm!/1)

        ebin_path

      {output, non_zero} ->
        raise CompileError,
          message: "Unable to build Elixir, make returned:\nexit: #{non_zero}\noutput: #{output}"
    end
  end

  defp with_tmp_dir(fun) when is_function(fun, 1) do
    rand_string = 8 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false)
    tmp_dir = Path.join([File.cwd!(), "tmp", rand_string])

    File.mkdir_p!(tmp_dir)

    try do
      fun.(tmp_dir)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp manifest_path do
    Path.join(Mix.Project.app_path(), ".lib_elixir")
  end

  defp get_manifest do
    manifest_path()
    |> File.read!()
    |> :erlang.binary_to_term()
  rescue
    _ -> %{libs: %{}}
  end

  defp write_manifest(manifest) do
    File.write!(manifest_path(), :erlang.term_to_binary(manifest))
  end

  defp clean_lib(module) do
    File.rm_rf(lib_path(module))
    :ok
  end

  defp lib_path(module) do
    app = Namespace.app_name(module)

    Path.join([Mix.Project.build_path(), "lib", to_string(app)])
  end

  defp lib_elixirs do
    app = Keyword.fetch!(Mix.Project.config(), :app)

    case :application.get_key(app, :modules) do
      {:ok, modules} ->
        Enum.flat_map(modules, fn module ->
          case LibElixir.fetch_ref(module) do
            {:ok, ref} -> [{module, ref}]
            :error -> []
          end
        end)

      _ ->
        []
    end
  end
end