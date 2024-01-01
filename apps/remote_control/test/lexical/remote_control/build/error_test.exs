defmodule Lexical.RemoteControl.Build.ErrorTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.ModuleMappings
  require Logger

  use ExUnit.Case
  use Patch

  setup do
    start_supervised!(Lexical.RemoteControl.Dispatch)
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

  describe "refine_diagnostics/1" do
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

      [normalized] = Build.Error.refine_diagnostics([diagnostic])

      assert normalized.message ==
               ":slave.stop/1 is deprecated. It will be removed in OTP 27. Use the 'peer' module instead"

      assert String.starts_with?(normalized.uri, "file://")
      assert String.ends_with?(normalized.uri, "lib/dummy.ex")
    end
  end

  describe "diagnostic/3" do
    setup do
      patch(ModuleMappings, :modules_in_file, fn _ -> [] end)
      :ok
    end

    test "handles undefined variable" do
      diagnostic =
        ~S[
        defmodule Foo do
          def bar do
            a
          end
        end
      ]
        |> compile()
        |> diagnostic()

      # TODO: span
      assert diagnostic.message =~ ~s[undefined variable "a"]
      assert diagnostic.position == {4, 13}
    end

    test "handles unsued warning"

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
        |> diagnostic()

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
        |> diagnostic()

      assert diagnostic.message =~ ~s[function :slave.stop/0 is undefined or private.]
      assert diagnostic.position == {3, 17}
    end

    test "handles UndefinedError for erlang function without defined module" do
      diagnostic =
        ~S[

         :slave.stop(:name, :name)
        ]
        |> compile()
        |> diagnostic()

      assert diagnostic.message =~ ~s[function :slave.stop/2 is undefined or private.]
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
        |> diagnostic()

      assert diagnostic.message =~
               ~s[undefined function print/1]

      # TODO: span
      # NOTE: main is {4, 13}
      assert diagnostic.position == 4
    end

    test "handles UndefinedError without moudle" do
      diagnostic =
        ~S[

          IO.ins
        ]
        |> compile()
        |> diagnostic()

      assert diagnostic.message =~ ~s[function IO.ins/0 is undefined or private]
      assert diagnostic.position == {3, 14}
    end

    test "handles ArgumentError" do
      diagnostics =
        ~s[String.to_integer ""]
        |> compile()
        |> diagnostics()

      [diagnostic | _] = diagnostics

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
        |> diagnostic()

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
        |> diagnostic()

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
        |> diagnostic()

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
        |> diagnostic()

      assert diagnostic.message =~ ~s[protocol Enumerable not implemented for 1 of type Integer]
      assert diagnostic.position == 3
    end

    test "handles Protocol.UndefinedError for comprehension when no module" do
      diagnostic =
        ~S[
          for i <- 1, do: i
        ]
        |> compile()
        |> diagnostic()

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
        |> diagnostic()

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
        |> diagnostic()

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
        |> diagnostic()

      assert diagnostic.message =~ ~s[describe \"foo\" is already defined in FooTest]
      assert diagnostic.position == 11
    end

    test "handles struct `KeyError` when is in a function block" do
      diagnostic =
        ~s(
        defmodule Foo do
          defstruct [:a, :b]
        end

        defmodule Bar do
          def bar do
            %Foo{c: :value}
          end
        end
        )
        |> compile()
        |> diagnostic()

      assert diagnostic.message =~ "key :c not found"
      assert diagnostic.position == 8
    end

    test "handles struct `CompileError` when is in a function params" do
      diagnostic =
        ~s/
        defmodule Foo do
          defstruct [:a, :b]
        end

        defmodule Bar do
          def bar(%Foo{c: c}) do
          end
        end
        /
        |> compile()
        |> diagnostic()

      assert diagnostic.message =~ "unknown key :c for struct Foo"

      if Features.with_diagnostics?() do
        assert diagnostic.position == {7, 19}
      else
        assert diagnostic.position == 7
      end
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
        |> diagnostic()

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
        |> diagnostic()

      assert diagnostic.message =~
               "record :user does not have the key: :email"

      assert diagnostic.position == 7
    end
  end
end
