defmodule Lexical.Server.CodeIntelligence.Completion.Translations.CallbackTest do
  use Lexical.Test.Server.CompletionCase

  describe "callback completions" do
    test "suggest callbacks", %{project: project} do
      source = ~q[
        defmodule MyServer do
          use GenServer
          def handle_inf|
        end
      ]

      {:ok, completion} =
        project
        |> complete(source)
        |> fetch_completion(kind: :function)

      assert apply_completion(completion) =~ "def handle_info(${1:msg}, ${2:state})"
    end

    test "do not add parens if they're already present", %{project: project} do
      source = ~q[
        defmodule MyServer do
          use GenServer
          def handle_inf|(msg, state)
        end
      ]

      {:ok, completion} =
        project
        |> complete(source)
        |> fetch_completion(kind: :function)

      assert apply_completion(completion) =~ "def handle_info(msg, state)"
    end
  end
end
