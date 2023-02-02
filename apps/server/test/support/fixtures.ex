defmodule Lexical.Test.Fixtures do
  alias Lexical.Project

  def project do
    [File.cwd!(), "test", "fixtures", "project"]
    |> Path.join()
    |> Lexical.SourceFile.Path.to_uri()
    |> Project.new()
  end
end
