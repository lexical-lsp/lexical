defmodule LibElixir.Artifact do
  @moduledoc false

  alias LibElixir.Namespace

  require Logger

  @base_url "https://github.com/elixir-lang/elixir/archive"

  @doc """
  Returns user cache directory.
  """
  def cache_dir do
    cache_dir = :filename.basedir(:user_cache, "lib_elixir")
    File.mkdir_p!(cache_dir)
    cache_dir
  end

  @doc """
  Returns the full path to a cached Elixir archive.
  """
  def elixir_archive_path(ref) do
    cache_path("elixirs", "#{ref}.tar.gz")
  end

  # @doc """
  # Compresses the given files to create an archive.
  # """
  # def compress_archive!(archive_path, paths) do
  #   :ok = :erl_tar.create(archive_path, paths, [:compressed])
  # end

  @doc """
  Extracts the given archive to a directory.
  """
  def extract_archive!(archive_path, directory) do
    :ok = :erl_tar.extract(archive_path, [:compressed, {:cwd, directory}])
  end

  @doc """
  Returns the full path to a code archive.
  """
  def ez_path(ref, name) do
    app_name = Namespace.app_name(name)
    cache_path(Path.join("code_archives", ref), "#{app_name}.ez")
  end

  @doc """
  Compresses the given directory to create a code archive.
  """
  def compress_ez!(ez_path, path) do
    original_cwd = File.cwd!()
    directory = Path.basename(path)

    File.cd!(Path.dirname(path))

    {:ok, _} =
      :zip.create(ez_path, [String.to_charlist(directory)],
        compress: :all,
        uncompress: [".beam", ".app"]
      )

    File.cd!(original_cwd)
  end

  @doc """
  Downloads an Elixir archive, unless already cached, returning the path.
  """
  def download_elixir_archive!(ref) do
    Application.ensure_all_started(:req)

    archive_path = elixir_archive_path(ref)

    if exists?(archive_path) do
      Mix.shell().info("[lib_elixir] Using cached Elixir archive: #{archive_path}")
    else
      Mix.shell().info("[lib_elixir] Downloading Elixir archive to: #{archive_path}")

      archive_stream = File.stream!(archive_path, [:write])
      archive_name = Path.basename(archive_path)
      archive_url = Path.join(@base_url, archive_name)

      %Req.Response{status: 200} = Req.get!(url: archive_url, into: archive_stream)
    end

    archive_path
  end

  @doc """
  Returns whether a given artifact exists.
  """
  def exists?(artifact_path) do
    case File.stat(artifact_path) do
      {:ok, %File.Stat{size: size}} when size > 0 -> true
      _ -> false
    end
  end

  defp cache_path(subdir, file) do
    file_dir = Path.join(cache_dir(), subdir)
    File.mkdir_p!(file_dir)
    Path.join(file_dir, file)
  end
end
