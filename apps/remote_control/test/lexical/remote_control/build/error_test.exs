defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.RemoteControl.Build.Error

  use ExUnit.Case, async: true

  def compile(source) do
    case Code.string_to_quoted(source) do
      {:ok, quoted_ast} ->
        try do
          modules = for {m, _b} <- Code.compile_quoted(quoted_ast), do: m
          {:ok, modules}
        rescue
          exception ->
            {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
            {:exception, filled_exception, stack, quoted_ast}
        end

      error ->
        error
    end
  end

  def parse_error({:error, {a, b, c}}) do
    Error.parse_error_to_diagnostics(a, b, c)
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

      assert normalized.message ==
               ":slave.stop/1 is deprecated. It will be removed in OTP 27. Use the 'peer' module instead"
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

      assert [error, detail] = errors
      assert error.message =~ "unexpected reserved word: end"
      assert error.position == {15, 9}

      assert detail.message =~ ~S[The "(" here is missing terminator ")"]
      assert detail.position == 4
    end
  end

  describe "error_to_diagnostic/3" do
    test "handles FunctionClauseError" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          def add(a, b) when is_integer(a) and is_integer(b) do
            a + b
          end
        end

        Foo.add("1", "2")
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[no function clause matching in Foo.add/2]
      assert diagnostic.position == 3
    end

    test "handles UndefinedError for erlang moudle" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
         :slave.stop
        end
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[function :slave.stop/0 is undefined or private.]
      assert diagnostic.position == 3
    end

    test "handles UndefinedError for erlang function without defined module" do
      {:exception, exception, stack, quoted_ast} = ~S[

         :slave.stop(:name, :name)
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[function :slave.stop/2 is undefined or private.]
      assert diagnostic.position == 3
    end

    test "handles UndefinedError" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          def bar do
            print(:bar)
          end
        end
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[undefined function print/1]

      assert diagnostic.position == 4
    end

    test "handles UndefinedError when unused" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          a
        end
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[undefined function a/0]

      assert diagnostic.position == 3
    end

    test "handles UndefinedError without moudle" do
      {:exception, exception, stack, quoted_ast} =
        ~S[

          IO.ins
        ]
        |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[function IO.ins/0 is undefined or private]
      assert diagnostic.position == 3
    end

    test "handles ArgumentError" do
      {:exception, exception, stack, quoted_ast} = ~s[String.to_integer ""] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
      assert diagnostic.position == 1
    end

    test "handles ArgumentError when in module" do
      {:exception, exception, stack, quoted_ast} = ~s[
        defmodule Foo do
          :a |> {1, 2}
        end
      ] |> compile()
      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[cannot pipe :a into {1, 2}, can only pipe into local calls foo()]

      assert diagnostic.position == 3
    end

    test "handles ArgumentError when in function" do
      {:exception, exception, stack, quoted_ast} = ~s[
        defmodule Foo do
          def foo do
            :a |> {1, 2}
          end
        end
      ] |> compile()
      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[cannot pipe :a into {1, 2}, can only pipe into local calls foo()]

      assert diagnostic.position == 4
    end

    test "can't find right line when use macro" do
      {:exception, exception, stack, quoted_ast} = ~S[
          Module.create(
            Foo,
            quote do
              String.to_integer("")
            end,
            file: "")
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
      assert diagnostic.position == nil
    end

    test "handles Protocol.UndefinedError for comprehension" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          for i <- 1, do: i
        end] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 3
    end

    test "handles Protocol.UndefinedError for comprehension when no module" do
      {:exception, exception, stack, quoted_ast} = ~S[
          for i <- 1, do: i
        ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 2
    end

    test "handles RuntimeError" do
      {:exception, exception, stack, quoted_ast} = ~S[
      defmodule Foo do
        raise RuntimeError.exception("This is a runtime error")
      end
      ] |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[This is a runtime error]

      assert diagnostic.position == 1
    end

    test "handles ExUnit.DuplicateTestError" do
      {:exception, exception, stack, quoted_ast} =
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

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[\"test foo\" is already defined in FooTest]
      assert diagnostic.position == 9
    end

    test "handles ExUnit.DuplicateDescribeError" do
      {:exception, exception, stack, quoted_ast} =
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

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[describe \"foo\" is already defined in FooTest]
      assert diagnostic.position == 11
    end
  end
end
