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
        |> fetch_completion(kind: :interface)

      assert apply_completion(completion) =~
               "@impl true\ndef handle_info(${1:msg}, ${2:state}) do"
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
        |> fetch_completion(kind: :interface)

      assert apply_completion(completion) =~
               "@impl true\ndef handle_info(${1:msg}, ${2:state}) do"
    end
  end
end
