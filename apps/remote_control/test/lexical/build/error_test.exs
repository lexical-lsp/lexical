defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.RemoteControl.Build.Error
  use ExUnit.Case

  def to_quoted(source) do
    Code.string_to_quoted(source)
  end

  def parse_error({:error, {a, b, c}}) do
    Error.parse_error_to_diagnostics(a, b, c)
  end

  describe "handling parse errors" do
    test "handles token missing errors" do
      assert [diagnostic] =
               ~s[%{foo: 3]
               |> to_quoted()
               |> parse_error()

      assert diagnostic.message =~ ~s[missing terminator: } (for "{" starting at line 1)]
    end

    test "returns both the error and the detail when provided" do
      errors =
        ~S[
        def handle_info(file_diagnostics(uri: uri, diagnostics: diagnostics), %State{} = state) do
        state = State.clear(state, uri)
        state = Enum.reduce(diagnostics, state, fn diagnostic, state ->
          case State.add(diagnostic, state, uri) do
            {:ok, new_state} ->
              new_state
            {:error, reason} ->
              Logger.error("Could not add diagnostic #{inspect(diagnostic)} because #{inspect(error)}")
              state
          end
        end

          publish_diagnostics(state)
        end
        ]
        |> to_quoted()
        |> parse_error()

      assert [error, detail] = errors
      assert error.message =~ "unexpected reserved word: end"
      assert error.position == {15, 9}

      assert detail.message =~ ~S[The "(" here is missing terminator ")"]
      assert detail.position == 4
    end
  end
end
