defmodule Lexical.Server.CodeIntelligence.Completion.Translations.StructFieldTest do
  use Lexical.Test.Server.CompletionCase

  test "a struct's fields are completed", %{project: project} do
    source = ~q[
      struct = %Project.Structs.User{}
      struct.f|
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.insert_text == "first_name"
    assert completion.detail == "first_name"
    assert completion.label == "first_name"
  end

  test "a struct's fields are completed when the struct is partially aliased", %{project: project} do
    source = ~q[
      alias Project.Structs
      struct = %Structs.User{}
      struct.f|
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.insert_text == "first_name"
    assert completion.detail == "first_name"
    assert completion.label == "first_name"
  end

  test "a struct's fields are completed when the struct is fully aliased", %{project: project} do
    source = ~q[
      alias Project.Structs.User
      struct = %User{}
      struct.f|
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.insert_text == "first_name"
    assert completion.detail == "first_name"
    assert completion.label == "first_name"
  end

  test "a struct's fields are completed when the struct is aliased using as", %{project: project} do
    source = ~q[
      alias Project.Structs.User, as: LocalUser
      struct = %LocalUser{}
      struct.f|
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.insert_text == "first_name"
    assert completion.detail == "first_name"
    assert completion.label == "first_name"
  end

  test "a struct defined in function arguments fields are completed", %{project: project} do
    source = ~q[
      defmodule MyModule do
        alias Project.Structs
        def my_fun(%Structs.User{} = user) do
          user.f|
        end
      end
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.insert_text == "first_name"
    assert completion.detail == "first_name"
    assert completion.label == "first_name"
  end

  describe "in struct arguments" do
    def my_module(text) do
      """
      defmodule MyModule do
        #{text}
      end
      """
    end

    test "should complete when after the curly", %{project: project} do
      {:ok, [completion, _]} =
        project
        |> complete(my_module("%Project.Structs.Account{|}"))
        |> fetch_completion(kind: :field)

      assert completion.insert_text == "last_login_at: ${1:last_login_at}"
      assert completion.insert_text_format == :snippet
      assert completion.kind == :field
      assert completion.label == "last_login_at: last_login_at"
    end

    test "should complete when after the comma", %{project: project} do
      {:ok, [_, completion]} =
        project
        |> complete(my_module("%Project.Structs.Account{last_login_at: nil, |}"))
        |> fetch_completion(kind: :field)

      assert completion.insert_text == "user: ${1:user}"
      assert completion.label == "user: user"
    end

    test "should complete even the struct module is aliased", %{project: project} do
      source = ~q[
        defmodule MyModule do
          alias Project.Structs.Account, as: LocalAccount

          def account(%LocalAccount{|} = account) do
            account
          end
        end
      ]

      {:ok, [completion, _]} =
        project
        |> complete(source)
        |> fetch_completion(kind: :field)

      assert completion.insert_text == "last_login_at: ${1:last_login_at}"
      assert completion.insert_text_format == :snippet
      assert completion.kind == :field
    end

    test "complete nothing when in the value position", %{project: project} do
      assert {:error, :not_found} ==
               project
               |> complete("%Project.Structs.Account{last_login_at: |}")
               |> fetch_completion(kind: :field)
    end

    test "complete nothing when the prefix is a tigger", %{project: project} do
      assert {:error, :not_found} ==
               project
               |> complete("%Project.Structs.Account{l.|}")
               |> fetch_completion(kind: :field)
    end

    test "complete nothing when the module is not a struct", %{project: project} do
      assert {:error, :not_found} ==
               project
               |> complete("%Project.Structs.NotAStruct{|}")
               |> fetch_completion(kind: :field)
    end
  end
end
