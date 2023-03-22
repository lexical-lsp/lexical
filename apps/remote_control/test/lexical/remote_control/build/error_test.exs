defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.RemoteControl.Build.Error

  use ExUnit.Case, async: true

  def to_quoted(source) do
    Code.string_to_quoted(source)
  end

  def parse_error({:error, {a, b, c}}) do
    Error.parse_error_to_diagnostics(a, b, c)
  end

  defp compile({:ok, quoted_ast}, file \\ "nofile") do
    try do
      Code.compile_quoted(quoted_ast, file)
    rescue
      exception ->
        {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
        {:exception, filled_exception, stack, quoted_ast}
    end
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

  describe "error_to_diagnostic/3" do
    test "handles UndefinedError for erlang moudle" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
         :slave.stop
        end
      ] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[function :slave.stop/0 is undefined or private.]
      assert diagnostic.position == 3
    end

    test "handles UndefinedError" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          def bar do
            print(:bar)
          end
        end
      ] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[undefined function print/1]

      assert diagnostic.position == 4
    end

    test "handles ArgumentError" do
      {:exception, exception, stack, quoted_ast} =
        ~s[String.to_integer ""] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
      assert diagnostic.position == 1
    end

    test "can't find right line when use macro" do
      {:exception, exception, stack, quoted_ast} = ~S[
          Module.create(
            Foo,
            quote do
              String.to_integer("")
            end,
            file: "")
      ] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[errors were found at the given arguments:]
      assert diagnostic.position == nil
    end

    test "handles Protocol.UndefinedError for comprehension" do
      {:exception, exception, stack, quoted_ast} = ~S[
        defmodule Foo do
          for i <- 1, do: i
        end] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 3
    end

    test "handles Protocol.UndefinedError for comprehension when no module" do
      {:exception, exception, stack, quoted_ast} = ~S[
          for i <- 1, do: i
        ] |> to_quoted() |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 2
    end

    test "handles RuntimeError" do
      # NOTE: its hard to trigger this error with unit test code, but its easy to encounter this error in a test file
      ~s[
      defmodule FooTest do
        use ExUnit.Case, async: true

        describe "dummy" do
        end

      end]

      # You can put these lines in a test file and delete the line 5 `end`, and wait a while to trigger this error

      {:exception, exception, stack, quoted_ast} =
        {:exception,
         %RuntimeError{
           message:
             "cannot use ExUnit.Case without starting the ExUnit application, please call ExUnit.start() or explicitly start the :ex_unit app"
         },
         [
           {ExUnit.Case, :__after_compile__, 2,
            [file: 'lib/ex_unit/case.ex', line: 505, error_info: %{module: Exception}]},
           {:elixir_module, :"-expand_callback/6-fun-0-", 6,
            [file: 'src/elixir_module.erl', line: 413]},
           {:elixir_module, :expand_callback, 6, [file: 'src/elixir_module.erl', line: 412]},
           {:lists, :foldl, 3, [file: 'lists.erl', line: 1350]},
           {:elixir_module, :compile, 6, [file: 'src/elixir_module.erl', line: 161]},
           {:elixir_compiler, :eval_or_compile, 3, [file: 'src/elixir_compiler.erl', line: 38]},
           {:elixir_lexical, :run, 3, [file: 'src/elixir_lexical.erl', line: 15]},
           {:elixir_compiler, :quoted, 3, [file: 'src/elixir_compiler.erl', line: 17]}
         ],
         {:defmodule, [do: [line: 1, column: 21], end: [line: 7, column: 1], line: 1, column: 1],
          [
            {:__aliases__, [last: [line: 1, column: 11], line: 1, column: 11], [:FooTest]},
            [
              do:
                {:__block__, [],
                 [
                   {:use,
                    [end_of_expression: [newlines: 2, line: 2, column: 31], line: 2, column: 3],
                    [
                      {:__aliases__, [last: [line: 2, column: 14], line: 2, column: 7],
                       [:ExUnit, :Case]},
                      [async: true]
                    ]},
                   {:describe,
                    [do: [line: 4, column: 20], end: [line: 5, column: 3], line: 4, column: 3],
                    ["dummy", [do: {:__block__, [], []}]]}
                 ]}
            ]
          ]}}

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~
               ~s[cannot use ExUnit.Case without starting the ExUnit application]

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
        |> to_quoted()
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
        |> to_quoted()
        |> compile()

      diagnostic = Error.error_to_diagnostic(exception, stack, quoted_ast)

      assert diagnostic.message =~ ~s[describe \"foo\" is already defined in FooTest]
      assert diagnostic.position == 11
    end
  end
end
