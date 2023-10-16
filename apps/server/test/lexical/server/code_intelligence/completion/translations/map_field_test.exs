defmodule Lexical.Server.CodeIntelligence.Completion.Translations.MapFieldTest do
  # alias Lexical.Server.CodeIntelligence.Completion.Translations.MapField
  use Lexical.Test.Server.CompletionCase

  use ExUnit.Case, async: true

  test "a map's fields are completed", %{project: project} do
    source = ~q[
      user = %{first_name: "John", last_name: "Doe"}
      user.f|
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert completion.detail == "first_name"
    assert apply_completion(completion) =~ "user.first_name"
  end

  test "a map's fields are completed after a dot", %{project: project} do
    source = ~q[
      user = %{first_name: "John", last_name: "Doe"}
      user.|
    ]

    assert {:ok, [first_name, last_name]} =
             project
             |> complete(source)
             |> fetch_completion(kind: :field)

    assert apply_completion(first_name) =~ "user.first_name"
    assert apply_completion(last_name) =~ "user.last_name"
  end
end
