defmodule Lexical.Server.CodeIntelligence.Completion.Translations.StructTest do
  use Lexical.Test.Server.CompletionCase

  describe "structs" do
    test "should complete after %", %{project: project} do
      assert {:ok, [_, _] = account_and_user} =
               project
               |> complete("%Project.Structs.|")
               |> fetch_completion(kind: :struct)

      assert Enum.find(account_and_user, &(&1.label == "User"))
      account = Enum.find(account_and_user, &(&1.label == "Account"))
      assert account
      assert account.insert_text == "Account{}"
      assert account.detail == "Account (Struct)"
    end

    test "should complete aliases after %", %{project: project} do
      source = ~q[
        alias Project.Structs.User
        def my_function(%Us|)
      ]
      assert [completion] = complete(project, source)

      assert completion.insert_text == "User{}"
      assert completion.kind == :struct
    end

    test "should complete, but not add curlies for aliases after %", %{project: project} do
      source = ~q[
        alias Project.Structs.User
        def my_function(%Us|{})
      ]
      assert [completion] = complete(project, source)

      assert completion.insert_text == "User"
      assert completion.kind == :struct
    end

    test "should complete module aliases and ends with {} after %", %{project: project} do
      source = ~q[
        defmodule TestModule do
        alias Project.Structs.User

        def my_function(%Us|)
      ]

      assert [completion] = complete(project, source)

      assert completion.insert_text == "User{}"
      assert completion.kind == :struct
    end

    test "should complete, but not add curlies when last word not contains %", %{project: project} do
      source = ~q[
        defmodule TestModule do
        alias Project.Structs.User

        Us|
      ]

      assert [completion] = complete(project, source)

      assert completion.insert_text == "User"
      assert completion.kind == :struct
    end

    test "should complete non-aliased correctly", %{project: project} do
      source = ~q[
        def my_function(%Project.Structs.U|)
      ]
      assert [completion] = complete(project, source)

      assert completion.insert_text == "User{}"
      assert completion.kind == :struct
    end

    test "does not add curlies if they're already present in a non-aliased reference", %{
      project: project
    } do
      source = ~q[
        def my_function(%Project.Structs.U|{})
      ]

      assert [completion] = complete(project, source)

      assert completion.insert_text == "User"
      assert completion.kind == :struct
    end

    test "when using %, only parents of a struct are returned", %{project: project} do
      assert [completion] = complete(project, "%Project.|", "%")
      assert completion.label == "Structs"
      assert completion.kind == :module
      assert completion.detail
    end

    test "when using %, only struct modules of are returned", %{project: project} do
      assert [_, _] = account_and_user = complete(project, "%Project.Structs.|", "%")
      assert Enum.find(account_and_user, &(&1.label == "Account"))
      assert Enum.find(account_and_user, &(&1.label == "User"))
    end

    test "it should complete struct fields", %{project: project} do
      source = ~q[
        defmodule Fake do
          alias Project.Structs.User
          def my_function(%User{} = u) do
            u.|
          end
        end
      ]

      assert fields = complete(project, source)

      assert length(fields) == 3
      assert Enum.find(fields, &(&1.label == "first_name"))
      assert Enum.find(fields, &(&1.label == "last_name"))
      assert Enum.find(fields, &(&1.label == "email_address"))
    end

    test "it should complete module structs", %{project: project} do
      source = ~q{
        defmodule NewStruct do
        defstruct [:name, :value]

        def my_function(%__|)
      }

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.label == "%__MODULE__{}"
      assert completion.detail == "%__MODULE__{}"
      assert completion.kind == :struct
    end

    test "it should complete module structs after characters are typed", %{project: project} do
      source = ~q{
        defmodule NewStruct do
        defstruct [:name, :value]

        def my_function(%__MO|)
      }

      assert {:ok, completion} =
               project
               |> complete(source)
               |> fetch_completion(kind: :struct)

      assert completion.label == "%__MODULE__{}"
      assert completion.detail == "%__MODULE__{}"
      assert completion.kind == :struct
    end

    test "can be aliased", %{project: project} do
      assert [completion] = complete(project, "alias Project.Structs.A|")

      assert completion.insert_text == "Account"
    end
  end
end
