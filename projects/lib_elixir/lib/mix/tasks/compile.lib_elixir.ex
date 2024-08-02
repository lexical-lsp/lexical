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
    manifest = get_manifest()

    case required_lib_elixir(manifest) do
      {:ok, {module, ref}} ->
        info("Compiling #{inspect(module)} (Elixir #{ref})")

        # clean_lib(module)
        compile(module, ref)

        manifest
        |> put_in([:libs, module], ref)
        |> write_manifest!()

        :ok

      _ ->
        info("Nothing to compile")
        :noop
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
    archive_path = Artifact.download_elixir_archive!(ref)

    with_tmp_dir(fn tmp_dir ->
      Artifact.extract_archive!(archive_path, tmp_dir)

      # The only top-level directory after extracting the archive
      # is the Elixir source directory
      [source_dir] = File.ls!(tmp_dir)
      source_dir = Path.join(tmp_dir, source_dir)

      ebin_path = compile_elixir_stdlib!(source_dir)
      Namespace.apply!(ebin_path, module)

      ez_path = Artifact.ez_path(ref, module)
      container_name = ez_path |> Path.basename() |> Path.rootname()
      container_path = Path.join(tmp_dir, container_name)
      container_ebin = Path.join(container_path, "ebin")

      File.mkdir_p!(container_ebin)
      File.cp_r!(ebin_path, container_ebin)
      Artifact.compress_ez!(ez_path, container_path)

      extract_ez(ez_path)
    end)

    :ok
  end

  defp extract_ez(ez_path) do
    ez_name = Path.basename(ez_path)
    target_dir = Path.join(Mix.Project.build_path(), "lib")

    IO.inspect(target_dir, label: "target_dir")

    target_ez = Path.join(target_dir, ez_name)

    File.cp!(ez_path, target_ez)
    {:ok, _} = :zip.unzip(~c"#{target_ez}", cwd: ~c"#{target_dir}")

    ez_root = Path.rootname(ez_name)
    File.cp_r!(Path.join(target_dir, ez_root), Path.join(target_dir, "lib_elixir"))
    File.rm_rf!(Path.join(target_dir, ez_root))

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

  defp write_manifest!(manifest) do
    File.write!(manifest_path(), :erlang.term_to_binary(manifest))
  end

  # defp clean_lib(module) do
  #   File.rm_rf(lib_path(module))
  #   :ok
  # end

  # defp lib_path(module) do
  #   app = Namespace.app_name(module)

  #   Path.join([Mix.Project.build_path(), "lib", to_string(app)])
  # end

  defp required_lib_elixir(manifest) do
    with {:ok, [{module, ref}]} <- Keyword.fetch(parent_config(), :lib_elixir),
         false <- manifest.libs[module] == ref do
      {:ok, {module, ref}}
    else
      _ -> :error
    end
  end

  defp info(message) do
    Mix.shell().info("[lib_elixir] #{message}")
  end

  defp parent_config do
    {_, %{config: parent_config}} = Mix.ProjectStack.top_and_bottom()
    parent_config
  end
end
