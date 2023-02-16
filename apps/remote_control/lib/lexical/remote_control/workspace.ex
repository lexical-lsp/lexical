defmodule Lexical.RemoteControl.Workspace do
  alias Lexical.Project
  @directory_name ".lexical"

  def ensure_exists(%Project{} = project) do
    directory_path = path(project)

    project
    |> Project.root_path()
    |> Path.join(@directory_name)

    cond do
      File.exists?(directory_path) and File.dir?(directory_path) ->
        :ok

      File.exists?(directory_path) ->
        :ok = File.rm(directory_path)
        :ok = File.mkdir_p(directory_path)

      true ->
        :ok = File.mkdir(directory_path)
    end
  end

  def build_directory(%Project{} = project) do
    project
    |> path()
    |> Path.join("build")
  end

  def path(%Project{} = project) do
    project
    |> Project.root_path()
    |> Path.join(@directory_name)
  end
end
