defmodule Lexical.Server.CodeIntelligence.CompletionTest do
  alias Lexical.Protocol.Types.Completion.List, as: CompletionList
  use Lexical.Test.Server.CompletionCase

  describe "excluding modules from lexical dependencies" do
    test "lexical modules are removed", %{project: project} do
      assert [] = complete(project, "Lexica|l")
    end

    test "Lexical submodules are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteContro|l")
    end

    test "Lexical functions are removed", %{project: project} do
      assert [] = complete(project, "Lexical.RemoteControl.|")
    end

    test "Dependency modules are removed", %{project: project} do
      assert [] = complete(project, "ElixirSense|")
    end

    test "Dependency functions are removed", %{project: project} do
      assert [] = complete(project, "Jason.encod|")
    end

    test "Dependency protocols are removed", %{project: project} do
      assert [] = complete(project, "Jason.Encode|")
    end

    test "Dependency structs are removed", %{project: project} do
      assert [] = complete(project, "Jason.Fragment|")
    end

    test "Dependency exceptions are removed", %{project: project} do
      assert [] = complete(project, "Jason.DecodeErro|")
    end
  end

  test "ensure completion works for project", %{project: project} do
    refute [] == complete(project, "Project.|")
  end

  describe "ignoring things" do
    test "return empty items and mark is_incomplete when single character contexts", %{
      project: project
    } do
      assert complete(project, "def my_thing() d|") == %CompletionList{
               is_incomplete: true,
               items: []
             }
    end
  end

  describe "sort_text" do
    test "dunder functions have the dunder removed in their sort_text", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enum.|")
               |> fetch_completion("__info__")

      assert completion.sort_text == "info/1"
    end

    test "dunder macros have the dunder removed in their sort_text", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Project.__dunder_macro__|")
               |> fetch_completion("__dunder_macro__")

      assert completion.sort_text == "dunder_macro/0"
    end
  end
end
