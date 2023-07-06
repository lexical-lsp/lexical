defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.RemoteControl.Build.Error

  use ExUnit.Case, async: true
  require Logger

  def compile(source) do
    doc = Document.new("file:///unknown.ex", source, 0)

    case Code.string_to_quoted(source, columns: true) do
      {:ok, quoted_ast} ->
        if System.version() >= "1.15" do
          do_compile_after_1_15(doc, quoted_ast)
        else
          do_compile(doc, quoted_ast)
        end

      error ->
        Logger.warning("error is #{inspect(error)}")
        {doc, error}
    end
  end

  defp do_compile(doc, quoted_ast) do
    try do
      modules = for {m, _b} <- Code.compile_quoted(quoted_ast, "/unknown.ex"), do: m
      {:ok, modules}
    rescue
      exception ->
        {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
        Logger.warning("Exception #{inspect(filled_exception)} stack: #{inspect(stack)}")
        {doc, {:exception, filled_exception, stack, quoted_ast}}
    end
  end

  defp do_compile_after_1_15(doc, quoted_ast) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.put_compiler_option(:parser_options, columns: true)

    {result, all_errors_and_warnings} =
      Code.with_diagnostics([log: true], fn ->
        try do
          modules = for {m, _b} <- Code.compile_quoted(quoted_ast, "/unknown.ex"), do: m
          {:ok, modules}
        rescue
          exception ->
            {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
            {:exception, filled_exception, stack, quoted_ast}
        end
      end)

    case {result, all_errors_and_warnings} do
      {{:ok, modules}, []} ->
        {:ok, modules}

      {{:ok, _}, all_errors_and_warnings} ->
        {doc, all_errors_and_warnings}

      {other, all_errors_and_warnings} ->
        {doc, other, all_errors_and_warnings}
    end
  end

  def parse_error({source, {:error, {a, b, c}}}) do
    Error.parse_error_to_diagnostics(source, a, b, c)
  end

  def error_to_diagnostic(
        {doc, {:exception, exception, stack, quoted_ast}, all_errors_and_warnings}
      ) do
    converted = Error.error_to_diagnostic(doc, exception, stack, quoted_ast)
    maybe_diagnostics = Error.diagnostics_from_mix(doc, all_errors_and_warnings)
    diagnostics = [converted | maybe_diagnostics] |> Enum.reverse() |> Error.uniq()
    [diagnostic] = diagnostics
    diagnostic
  end

  def error_to_diagnostic({doc, all_errors_and_warnings}) when is_list(all_errors_and_warnings) do
    [diagnostic] = Error.diagnostics_from_mix(doc, all_errors_and_warnings)
    diagnostic
  end

  def error_to_diagnostic({source, {:exception, exception, stack, quoted_ast}}) do
    Error.error_to_diagnostic(source, exception, stack, quoted_ast)
  end

  describe "normalize_diagnostic/1" do
    test "normalizes the message when its a iodata" do
      diagnostic = %Mix.Task.Compiler.Diagnostic{
        file: "lib/dummy.ex",
        severity: :warning,
        message: [
          ":slave.stop/1",
          " is deprecated. ",
          "It will be removed in OTP 27. Use the 'peer' module instead"
        ],
        position: 6,
        compiler_name: "Elixir",
        details: nil
      }

      normalized = Error.normalize_diagnostic(diagnostic)
      assert %Diagnostic.Result{} = normalized

      assert normalized.message ==
               ":slave.stop/1 is deprecated. It will be removed in OTP 27. Use the 'peer' module instead"

      assert String.starts_with?(normalized.uri, "file://")
      assert String.ends_with?(normalized.uri, "lib/dummy.ex")
    end
  end

  describe "handling parse errors" do
    test "handles token missing errors" do
      assert [diagnostic] =
               ~s[%{foo: 3]
               |> compile()
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
        |> compile()
        |> parse_error()

      # assert [error, detail] = errors
      assert [detail, error] = errors

      assert error.message =~ "unexpected reserved word: end"
      assert error.position == {15, 9}

      assert detail.message =~ ~S["(" here is missing terminator ")"]
      assert detail.position == 4
    end

    test "return the more precise one when there are multiple diagnostics on the same line" do
      errors =
        ~S{Keywor.get([], fn x -> )}
        |> compile()
        |> parse_error()

      assert [error] = errors

      assert error.message =~
               ~S[unexpected token: )]

      assert error.position == {1, 24}
    end

    test "returns two diagnostics when missing end at the real end" do
      errors =
        ~S[
        defmodule Foo do
          def bar do
            :ok
        end]
        |> compile()
        |> parse_error()

      assert [end_diagnostic, start_diagnostic] = errors

      assert %Diagnostic.Result{} = end_diagnostic
      assert end_diagnostic.message == "missing terminator: end (for \"do\" starting at line 2)"
      assert end_diagnostic.position == {5, 12}

      assert %Diagnostic.Result{} = start_diagnostic
      assert start_diagnostic.message == ~S[The "do" here is missing a terminator: "end"]
      assert start_diagnostic.position == 2
    end

    test "returns the token in the message when there is a token" do
      errors = ~S[1 + * 3] |> compile() |> parse_error()
      [end_diagnostic] = errors
      assert end_diagnostic.message == "syntax error before: '*'"
      assert end_diagnostic.position == {1, 5}
    end

    test "returns the approximate correct location when there is a hint." do
      errors = ~S[
        defmodule Foo do
          def bar_missing_end do
            :ok

          def bar do
            :ok
          end
        end] |> compile() |> parse_error()

      [end_message, start_message, hint_message] = errors

      assert end_message.message == ~S[missing terminator: end (for "do" starting at line 2)]
      assert end_message.position == {9, 12}

      assert start_message.message == ~S[The "do" here is missing a terminator: "end"]
      assert start_message.position == 2

      assert hint_message.message ==
               ~S[HINT: it looks like the "do" here does not have a matching "end"]

      assert hint_message.position == 3
    end

    test "returns the last approximate correct location when there are multiple missing" do
      errors = ~S[
        defmodule Foo do
          def bar_missing_end do
            :ok

          def bar_missing_end2 do

          def bar do
            :ok
          end
        end] |> compile() |> parse_error()

      [end_message, start_message, hint_message] = errors

      assert end_message.message == ~S[missing terminator: end (for "do" starting at line 3)]
      assert end_message.position == {11, 12}

      assert start_message.message == ~S[The "do" here is missing a terminator: "end"]
      assert start_message.position == 3

      assert hint_message.message ==
               ~S[HINT: it looks like the "do" here does not have a matching "end"]

      assert hint_message.position == 6
    end
  end

  describe "error_to_diagnostic/3" do
    test "handles FunctionClauseError" do
      diagnostic =
        ~S[
        defmodule Foo do
          def add(a, b) when is_integer(a) and is_integer(b) do
            a + b
          end
        end

        Foo.add("1", "2")
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[no function clause matching in Foo.add/2]
      assert diagnostic.position == 3
    end

    test "handles UndefinedError for erlang moudle" do
      diagnostic =
        ~S[
        defmodule Foo do
         :slave.stop
        end
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[function :slave.stop/0 is undefined or private.]
      assert diagnostic.position == {3, 17}
      # assert diagnostic.position == 3
    end

    test "handles UndefinedError for erlang function without defined module" do
      diagnostic =
        ~S[

         :slave.stop(:name, :name)
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[function :slave.stop/2 is undefined or private.]
      # assert diagnostic.position == 3
      assert diagnostic.position == {3, 17}
    end

    test "handles UndefinedError" do
      diagnostic =
        ~S[
        defmodule Foo do
          def bar do
            print(:bar)
          end
        end
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               ~s[undefined function print/1]

      # NOTE: main is {4, 13}
      assert diagnostic.position == 4
    end

    test "handles UndefinedError without moudle" do
      diagnostic =
        ~S[

          IO.ins
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[function IO.ins/0 is undefined or private]
      # assert diagnostic.position == 3
      assert diagnostic.position == {3, 14}
    end

    test "handles ArgumentError" do
      diagnostic =
        ~s[String.to_integer ""]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
    end

    test "handles ArgumentError when in module" do
      diagnostic =
        ~s[
        defmodule Foo do
          :a |> {1, 2}
        end
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               ~s[cannot pipe :a into {1, 2}, can only pipe into local calls foo()]

      assert diagnostic.position == 3
    end

    test "handles ArgumentError when in function" do
      diagnostic =
        ~s[
        defmodule Foo do
          def foo do
            :a |> {1, 2}
          end
        end
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               ~s[cannot pipe :a into {1, 2}, can only pipe into local calls foo()]

      assert diagnostic.position == 4
    end

    test "can't find right line when use macro" do
      diagnostic =
        ~S[
          Module.create(
            Foo,
            quote do
              String.to_integer("")
            end,
            file: "")
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
      assert diagnostic.position == nil
    end

    test "handles Protocol.UndefinedError for comprehension" do
      diagnostic =
        ~S[
        defmodule Foo do
          for i <- 1, do: i
        end]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 3
    end

    test "handles Protocol.UndefinedError for comprehension when no module" do
      diagnostic =
        ~S[
          for i <- 1, do: i
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 2
    end

    test "handles RuntimeError" do
      diagnostic =
        ~S[
      defmodule Foo do
        raise RuntimeError.exception("This is a runtime error")
      end
      ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               ~s[This is a runtime error]

      assert diagnostic.position == 1
    end

    test "handles ExUnit.DuplicateTestError" do
      diagnostic =
        ~s[
        defmodule FooTest do
          use ExUnit.Case, async: true

          test "foo" do
            assert 1 == 1
          end

          test "foo" do
            assert 1 == 1
          end
        end
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[\"test foo\" is already defined in FooTest]
      assert diagnostic.position == 9
    end

    test "handles ExUnit.DuplicateDescribeError" do
      diagnostic =
        ~s[
        defmodule FooTest do
          use ExUnit.Case, async: true

          describe "foo" do
            test "foo" do
              assert 1 == 1
            end
          end

          describe "foo" do
            test "foo" do
              assert 1 == 1
            end
          end
        end
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~ ~s[describe \"foo\" is already defined in FooTest]
      assert diagnostic.position == 11
    end

    test "handles struct enforce key error" do
      diagnostic =
        ~s(
        defmodule Foo do
          @enforce_keys [:a, :b]
          defstruct [:a, :b]
        end

        defmodule Bar do
          def bar do
            %Foo{}
          end
        end
        )
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               "the following keys must also be given when building struct Foo: [:a, :b]"

      assert diagnostic.position == 9
    end

    test "handles record missing key's error" do
      diagnostic =
        ~s[
        defmodule Bar do
          import Record
          defrecord :user, name: nil, age: nil

          def bar do
            u = user(name: "John", email: "")
          end
        end
        ]
        |> compile()
        |> error_to_diagnostic()

      assert diagnostic.message =~
               "record :user does not have the key: :email"

      assert diagnostic.position == 7
    end
  end
end
