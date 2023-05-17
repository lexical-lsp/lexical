defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviourTest do
  use Lexical.Test.Server.CompletionCase

  describe "module completions" do
    test "modules should emit a completion for stdlib modules", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enu|")
               |> fetch_completion(label: "Enum", kind: :module)

      assert completion.kind == :module
      assert completion.label == "Enum"
      assert completion.detail
    end

    test "modules should emit a completion for project modules without docs", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Projec|")
               |> fetch_completion(kind: :module)

      assert completion.kind == :module
      assert completion.label == "Project"
      assert completion.detail =~ "Project"
    end

    test "struct modules should emit a completion as a module", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Project.Structs.Us|")
               |> fetch_completion(kind: :module)

      assert completion.kind == :module
      assert completion.label == "User"
      assert completion.detail =~ "(Module)"
    end

    test "behaviours should emit a completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("GenS|")
               |> fetch_completion(kind: :module)

      assert completion.kind == :module
      assert completion.label == "GenServer"
      assert completion.detail =~ "A behaviour module"
    end

    test "protocols should emit a completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enumer|")
               |> fetch_completion(kind: :module)

      assert completion.kind == :module
      assert completion.label == "Enumerable"
      assert completion.detail =~ "Enumerable protocol"
    end
  end

  describe "struct references" do
    test "should work for top-level elixir structse", %{project: project} do
      source = ~q[
        %Map|
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.insert_text_format == :snippet
      assert completion.label == "%MapSet"
      assert completion.insert_text == "%MapSet{$1}"
      assert completion.detail == "MapSet (Struct)"
    end

    test "modules that define a struct should emit curlies if in a struct reference", %{
      project: project
    } do
      source = ~q[
        alias Project.Structs
        def my_thing(%Structs.U|) do
        end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.insert_text == "User{$1}"
      assert completion.detail == "User (Struct)"
    end

    test "modules that define a struct should not emit curlies if they're already present", %{
      project: project
    } do
      source = ~q[
      alias Project.Structs
      def my_thing(%Structs.U|{}) do
      end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.insert_text == "User"
      assert completion.detail == "User (Struct)"
    end

    test "should offer no other types of completions", %{project: project} do
      assert [] = complete(project, "%MapSet.|")
      assert [account, user] = complete(project, "%Project.|")
      assert account.label == "%Structs.Account"
      assert user.label == "%Structs.User"
    end
  end
end
