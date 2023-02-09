defmodule Lexical.Test.Fixtures do
  alias Lexical.Project

  def project do
    [Path.dirname(__ENV__.file), "..", "fixtures", "project"]
    |> Path.join()
    |> Path.expand()
    |> Lexical.SourceFile.Path.to_uri()
    |> Project.new()
  end
end
