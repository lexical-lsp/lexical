defmodule Lexical.RemoteControl.Bootstrap do
  @moduledoc """
  Bootstraps the remote control node boot sequence.

  We need to first start elixir and mix, then load the project's mix.exs file so we can discover
  the project's code paths, which are then added to the code paths from the language server. At this
  point, it's safe to start the project, as we should have all the code present to compile the system.
  """
  alias Lexical.Project

  def init(%Project{} = project) do
    project_root = Project.root_path(project)

    with {:ok, _} <- Application.ensure_all_started(:elixir),
         {:ok, _} <- Application.ensure_all_started(:mix),
         :ok <- File.cd(project_root),
         {:ok, mix_project} <- load_mix_exs(project),
         load_project_build_paths(mix_project) do
      Mix.start()
    end
  end

  defp load_project_build_paths(_mix_module) do
    [Mix.Project.build_path(), "lib", "**", "ebin"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(&String.to_charlist/1)
    |> :code.add_pathsz()

    :ok
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

  def load_mix_exs(%Project{} = project) do
    with {:ok, mix_exs_path} <- find_mix_exs(project),
         {:ok, [project_module], _} <- Kernel.ParallelCompiler.compile([mix_exs_path]) do
      {:ok, project_module}
    end
  end
end
