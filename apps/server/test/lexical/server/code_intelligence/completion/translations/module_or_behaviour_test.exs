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
      assert completion.detail =~ "Project.Structs.User"
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

  describe "erlang module completions" do
    test "unquoted atoms that are modules should emit a completion", %{project: project} do
      assert {:ok, completion} =
               project
               |> complete(":erla|")
               |> fetch_completion(":erlang")

      assert completion.kind == :module
      assert apply_completion(completion) == ":erlang"
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
      assert completion.label == "MapSet"
      assert completion.detail == "MapSet"
      assert apply_completion(completion) == "%MapSet{$1}\n"
    end

    test "should work for aliased struct", %{project: project} do
      source = ~q[
        alias Project.Structs.Account, as: MyAccount
        %My|
      ]

      expected = ~q[
        alias Project.Structs.Account, as: MyAccount
        %MyAccount{$1}
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert apply_completion(completion) == expected
    end

    test "modules that define a struct should emit curlies if in a struct reference", %{
      project: project
    } do
      source = ~q[
        alias Project.Structs
        def my_thing(%Structs.U|) do
        end
      ]

      expected = ~q[
        alias Project.Structs
        def my_thing(%Structs.User{$1}) do
        end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.detail == "Project.Structs.User"
      assert apply_completion(completion) == expected
    end

    test "a completion with curlies in the suffix should not have them added", %{project: project} do
      source = ~q[
        def my_thing(%Project.Structs.A|{}) do
      end
      ]

      expected = ~q[
        def my_thing(%Project.Structs.Account{}) do
      end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert apply_completion(completion) == expected
    end

    test "A module without a dot should have a percent added", %{project: project} do
      source = ~q[
        alias Project.Structs.Account
        def my_thing(%A|) do
      ]

      expected = ~q[
        alias Project.Structs.Account
        def my_thing(%Account{$1}) do
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.label == "Account"
      assert apply_completion(completion) == expected
    end

    test "A module with a dot in it should not have a percent added", %{project: project} do
      source = ~q[
        def my_thing(%Project.Structs.A|) do
      ]

      expected = ~q[
        def my_thing(%Project.Structs.Account{$1}) do
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.label == "Account"
      assert apply_completion(completion) == expected
    end

    test "modules that define a struct should not emit curlies if they're already present", %{
      project: project
    } do
      source = ~q[
      alias Project.Structs
      def my_thing(%Structs.U|{}) do
      end
      ]

      expected = ~q[
      alias Project.Structs
      def my_thing(%Structs.User{}) do
      end
      ]

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.detail == "Project.Structs.User"
      assert apply_completion(completion) == expected
    end

    test "should offer no other types of completions", %{project: project} do
      assert [] = complete(project, "%MapSet.|")

      assert [completion] = complete(project, "%Project.|")

      assert completion.label == "Structs...(4 more structs)"
      assert completion.detail == "Project.Structs."
    end

    test "should offer two completions when there are struct and its descendants", %{
      project: project
    } do
      source = ~q[
        alias Project.Structs.Order
        %Ord|
      ]

      [order, order_line] = complete(project, source)

      assert order_line.label == "Order...(1 more struct)"
      assert order_line.kind == :module
      assert apply_completion(order_line) =~ "%Order."

      assert order.label == "Order"
      assert order.kind == :struct
      assert apply_completion(order) =~ "%Order{$1}"
    end

    test "completions in use directives only return modules who have a descendent that has __using__",
         %{
           project: project
         } do
      source = ~q[
        use En|
      ]

      assert [ex_unit_completion, ex_unit_properties_completion] = complete(project, source)

      assert apply_completion(ex_unit_completion) =~ "use ExUnit"
      assert apply_completion(ex_unit_properties_completion) =~ "use ExUnitProperties"
    end
  end
end
