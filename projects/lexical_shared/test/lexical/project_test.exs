defmodule Lexical.ProjectTest do
  alias Lexical.Project

  use ExUnit.Case, async: false
  use ExUnitProperties
  use Patch

  def project do
    root = Lexical.Document.Path.to_uri(__DIR__)
    Project.new(root)
  end

  describe "name/1" do
    test "a project's name starts with a lowercase character and contains alphanumeric characters and _" do
      check all folder_name <- string(:ascii, min_length: 1) do
        patch Project, :folder_name, folder_name
        assert Regex.match?(~r/[a-z][a-zA-Z_]*/, Project.name(project()))
      end
    end

    test "periods are repleaced with underscores" do
      patch(Project, :folder_name, "foo.bar")
      assert Project.name(project()) == "foo_bar"
    end

    test "leading capital letters are downcased" do
      patch(Project, :folder_name, "FooBar")
      assert Project.name(project()) == "fooBar"
    end

    test "leading numbers are replaced with p_" do
      patch(Project, :folder_name, "3bar")
      assert Project.name(project()) == "p_3bar"
    end
  end
end
