defmodule Lexical.Test.Fixtures do
  alias Lexical.Project
  alias Lexical.SourceFile

  def project do
    [Path.dirname(__ENV__.file), "..", "fixtures", "project"]
    |> Path.join()
    |> Path.expand()
    |> Lexical.SourceFile.Path.to_uri()
    |> Project.new()
  end

  def file_path(%Project{} = project, path_relative_to_project) do
    project
    |> Project.project_path()
    |> Path.join(path_relative_to_project)
    |> Path.expand()
  end

  def file_uri(%Project{} = project, relative_path) do
    project
    |> file_path(relative_path)
    |> SourceFile.Path.ensure_uri()
  end
end
