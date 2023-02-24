defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.RemoteControl.Build.Error
  use ExUnit.Case

  def to_quoted(source) do
    Code.string_to_quoted(source)
  end

  def parse_error({:error, {a, b, c}}) do
    Error.parse_error_to_diagnostic(a, b, c)
  end

  describe "handling parse errors" do
    test "should be nice" do
      error =
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

      assert error.message =~ "unexpected reserved word: end"
      assert error.message =~ "The \"(\" at line 4 is missing terminator \")"
    end
  end
end
