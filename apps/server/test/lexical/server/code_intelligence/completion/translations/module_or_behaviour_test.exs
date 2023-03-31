defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleOrBehaviourTest do
  use Lexical.Test.Server.CompletionCase

  describe "module completions" do
    test "modules should emit a completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete("Enu|")
               |> fetch_completion(kind: :module)

      assert completion.kind == :module
      assert completion.label == "Enum"
      assert completion.detail
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
  end

  describe "struct references" do
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

      assert completion.insert_text == "User{}"
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
  end
end
