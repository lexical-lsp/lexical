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
end
