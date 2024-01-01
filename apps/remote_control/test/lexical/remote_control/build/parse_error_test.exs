defmodule Lexical.RemoteControl.Build.ParseErrorTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.RemoteControl.Build

  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.Dispatch

  use ExUnit.Case, async: true

  setup do
    start_supervised!(Dispatch)
    start_supervised!(CaptureServer)
    :ok
  end

  def compile(source) do
    doc = Document.new("file:///unknown.ex", source, 0)
    Build.Document.compile(doc)
  end

  def diagnostics({:error, diagnostics}) do
    diagnostics
  end

  def diagnostic({:error, [diagnostic]}) do
    diagnostic
  end

  describe "handling parse errors" do
    test "handles token missing errors" do
      assert diagnostics =
               ~s[%{foo: 3]
               |> compile()
               |> diagnostics()

      if Features.details_in_context?() do
        [end_diagnostic, start_diagnostic] = diagnostics

        assert start_diagnostic.message ==
                 ~s[The "{" here is missing terminator "}"]

        assert start_diagnostic.position == {1, 2, 1, 3}

        assert end_diagnostic.message == ~s[missing terminator: }]
        assert end_diagnostic.position == {1, 9}
      else
        [diagnostic] = diagnostics
        assert diagnostic.message =~ ~s[missing terminator: }]
        assert diagnostic.position == {1, 9}
      end
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
        |> compile()
        |> diagnostics()

      assert [error, detail] = errors

      assert error.message =~ "unexpected reserved word: end"
      assert error.position == {15, 9}

      assert String.downcase(detail.message) =~ ~S[the "(" here is missing terminator ")"]
      assert detail.position in [4, {4, 28, 4, 29}]
    end

    test "return the more precise one when there are multiple diagnostics on the same line" do
      [end_diagnostic, start_diagnostic] =
        ~S{Keywor.get([], fn x -> )}
        |> compile()
        |> diagnostics()

      assert end_diagnostic.message in [
               ~S[unexpected token: )],
               ~S[unexpected token: ), expected: "end"]
             ]

      assert end_diagnostic.position == {1, 24}

      assert String.downcase(start_diagnostic.message) =~
               ~S[the "fn" here is missing terminator "end"]

      assert start_diagnostic.position in [1, {1, 16, 1, 18}]
    end

    test "returns two diagnostics when missing end at the real end" do
      errors =
        ~S[
        defmodule Foo do
          def bar do
            :ok
        end]
        |> compile()
        |> diagnostics()

      assert [end_diagnostic, start_diagnostic] = errors

      assert %Diagnostic.Result{} = end_diagnostic
      assert end_diagnostic.message =~ "missing terminator: end"
      assert end_diagnostic.position == {5, 12}

      assert %Diagnostic.Result{} = start_diagnostic
      assert start_diagnostic.message == ~S[The "do" here is missing terminator "end"]
      assert start_diagnostic.position in [2, {2, 23, 2, 25}]
    end

    test "returns the token in the message when there is a token" do
      diagnostic = ~S[1 + * 3] |> compile() |> diagnostic()
      assert diagnostic.message == "syntax error before: '*'"
      assert diagnostic.position == {1, 5}
    end

    test "returns the approximate correct location when there is a hint." do
      diagnostics = ~S[
        defmodule Foo do
          def bar_missing_end do
            :ok

          def bar do
            :ok
          end
        end] |> compile() |> diagnostics()

      [end_message, start_message, hint_message] = diagnostics

      # TODO: I think we should remove the `hint`
      # assert end_message.message == ~S[missing terminator: end (for "do" starting at line 2)]
      assert end_message.position == {9, 12}

      assert start_message.message == ~S[The "do" here is missing terminator "end"]
      assert start_message.position in [2, {2, 23, 2, 25}]

      assert hint_message.message ==
               ~S[HINT: it looks like the "do" here does not have a matching "end"]

      assert hint_message.position == 3
    end

    test "returns the last approximate correct location when there are multiple missing" do
      diagnostics = ~S[
        defmodule Foo do
          def bar_missing_end do
            :ok

          def bar_missing_end2 do

          def bar do
            :ok
          end
        end] |> compile() |> diagnostics()

      [end_message, start_message, hint_message] = diagnostics

      # assert end_message.message == ~S[missing terminator: end (for "do" starting at line 3)]
      assert end_message.position == {11, 12}

      assert start_message.message == ~S[The "do" here is missing terminator "end"]
      assert start_message.position in [3, {3, 31, 3, 33}]

      assert hint_message.message ==
               ~S[HINT: it looks like the "do" here does not have a matching "end"]

      assert hint_message.position == 6
    end
  end
end
