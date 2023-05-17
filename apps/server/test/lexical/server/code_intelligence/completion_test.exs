defmodule Lexical.Server.CodeIntelligence.CompletionTest do
  alias Lexical.Protocol.Types.Completion
  alias Lexical.RemoteControl.Completion.Result

  use Lexical.Test.Server.CompletionCase
  use Patch

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
      assert complete(project, "def my_thing() d|") == %Completion.List{
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

  def with_all_completion_candidates(_) do
    name = "Foo"
    full_name = "A.B.Foo"

    all_completions = [
      %Result.Behaviour{name: "#{name}-behaviour", full_name: full_name},
      %Result.BitstringOption{name: "#{name}-bitstring", type: "integer"},
      %Result.Callback{name: "#{name}-callback", origin: full_name},
      %Result.Exception{name: "#{name}-exception", full_name: full_name},
      %Result.Function{name: "my_func", origin: full_name, argument_names: [], metadata: %{}},
      %Result.Macro{name: "my_macro", origin: full_name, argument_names: [], metadata: %{}},
      %Result.MixTask{name: "#{name}-mix-task", full_name: full_name},
      %Result.Module{name: "#{name}-module", full_name: full_name},
      %Result.ModuleAttribute{name: "#{name}-module-attribute"},
      %Result.Protocol{name: "#{name}-protocol", full_name: full_name},
      %Result.Struct{name: "#{name}-struct", full_name: full_name},
      %Result.StructField{name: "#{name}-struct-field", origin: full_name},
      %Result.Typespec{name: "#{name}-typespec"},
      %Result.Variable{name: "#{name}-variable"}
    ]

    patch(Lexical.RemoteControl.Api, :complete, all_completions)
    :ok
  end

  describe "context aware inclusions and exclusions" do
    setup [:with_all_completion_candidates]

    test "only modules and module-like completions are returned in an alias", %{project: project} do
      completions = complete(project, "alias Foo.")

      for completion <- complete(project, "alias Foo.") do
        assert %_{kind: :module} = completion
      end

      assert {:ok, _} = fetch_completion(completions, label: "Foo-behaviour")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-module")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-protocol")
      assert {:ok, _} = fetch_completion(completions, label: "Foo-struct")
    end
  end
end
