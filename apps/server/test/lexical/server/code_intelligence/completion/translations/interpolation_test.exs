defmodule Lexical.Server.CodeIntelligence.Completion.Translations.InterpolationTest do
  use Lexical.Test.Server.CompletionCase

  test "variables are completed inside strings", %{project: project} do
    source =
      ~S[
       variable = 3
       "#{var|}"
      ]
      |> String.trim()

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :variable)

    expected =
      ~S[
       variable = 3
       "#{variable}"
      ]
      |> String.trim()

    assert apply_completion(completion) == expected
  end

  test "erlang modules are completed inside strings", %{project: project} do
    source = ~S[
      "#{:erlan|}"
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(label: ":erlang")

    assert String.trim(apply_completion(completion)) == ~S["#{:erlang}"]
  end

  test "elixir modules are completed inside strings", %{project: project} do
    source = ~S[
      "#{Kern|}"
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(label: "Kernel")

    assert String.trim(apply_completion(completion)) == ~S["#{Kernel}"]
  end

  test "structs are completed inside strings", %{project: project} do
    source = ~S[
      "#{inspect(%Project.Structs.Us|)}"
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :struct)

    assert String.trim(apply_completion(completion)) ==
             ~S["#{inspect(%Project.Structs.User{$1})}"]
  end
end
