defmodule Lexical.Server.CodeIntelligence.Completion.Translations.VariableTest do
  use Lexical.Test.Server.CompletionCase

  test "variables are completed", %{project: project} do
    source = ~q[
      def my_function do
        stinky = :smelly
        st|
      end
    ]

    assert {:ok, completion} =
             project
             |> complete(source)
             |> fetch_completion(kind: :variable)

    assert completion.label == "stinky"
    assert completion.detail == "stinky"

    assert apply_completion(completion) == ~q[
      def my_function do
        stinky = :smelly
        stinky
      end
    ]
  end

  test "all variables are returned", %{project: project} do
    source = ~q[
    def my_function do
      var_1 = 3
      var_2 = 5
      va|
    end
    ]

    assert {:ok, [c1, c2]} =
             project
             |> complete(source)
             |> fetch_completion(kind: :variable)

    assert c1.label == "var_1"
    assert c2.label == "var_2"
  end
end
