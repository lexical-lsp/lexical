defmodule Lexical.RemoteControl.Build.StateTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.State
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.SourceFile
  alias Mix.Task.Compiler.Diagnostic

  import Messages
  import Lexical.Test.Fixtures

  import Testing.EventualAssertions
  use ExUnit.Case, async: false
  use Patch

  setup do
    {:ok, _} = start_supervised(Build.CaptureServer)
    :ok
  end

  def source_file(%State{} = state, filename \\ "file.ex", source_code) do
    sequence = System.unique_integer([:monotonic, :positive])

    uri =
      state.project
      |> Project.root_path()
      |> Path.join(to_string(sequence))
      |> Path.join(filename)
      |> SourceFile.Path.to_uri()

    SourceFile.new(uri, source_code, 0)
  end

  def compile_source_file(%State{} = state, filename \\ "file.ex", source_code) do
    source = source_file(state, filename, source_code)
    State.compile_file(state.project, source)
  end

  def with_project_state(project_name) do
    test = self()

    patch(RemoteControl, :notify_listener, fn msg ->
      send(test, msg)
    end)

    project_name = to_string(project_name)
    fixture_dir = Path.join(fixtures_path(), project_name)
    project = Project.new("file://#{fixture_dir}")
    state = State.new(project)

    RemoteControl.set_project(project)
    {:ok, state}
  end

  def with_empty_module(%{state: %State{} = state}) do
    module = ~S[
      defmodule UnderTest do
        def test?, do: true
      end
    ]
    compile_source_file(state, module)

    on_exit(fn ->
      :code.purge(UnderTest)
      :code.delete(UnderTest)
    end)

    assert_receive file_compiled(), 5000
    :ok
  end

  def with_metadata_project(_) do
    {:ok, state} = with_project_state(:project_metadata)
    {:ok, state: state}
  end

  def with_parse_errors_project(_) do
    {:ok, state} = with_project_state(:parse_errors)
    {:ok, state: state}
  end

  describe "compile_project/2" do
    test "sends a message when complete " do
      {:ok, state} = with_project_state(:project_metadata)
      State.compile_project(state, true)

      assert_receive project_compiled(status: :success), 5000
    end

    test "receives diagnostics" do
      {:ok, state} = with_project_state(:project_metadata)

      State.compile_project(state, true)
      assert_receive project_diagnostics(), 5000
    end

    test "it sends a message when compilation of an umbrella project is complete" do
      {:ok, state} = with_project_state(:umbrella)
      State.compile_project(state, true)

      assert_receive project_compiled(status: :success), 5000
      assert_receive project_diagnostics(diagnostics: [])
    end

    test "it reports the errors if the project has errors" do
      {:ok, state} = with_project_state(:compilation_errors)
      State.compile_project(state, true)

      assert_receive project_compiled(status: :error), 5000
      assert_receive project_diagnostics(diagnostics: [%Diagnostic{}])
    end

    test "it sends a message when the the project has parse errors" do
      {:ok, state} = with_project_state(:parse_errors)
      State.compile_project(state, true)

      assert_receive project_compiled(status: :error), 5000
      assert_receive project_diagnostics(diagnostics: [%Diagnostic{} = diagnostic])

      assert diagnostic.message =~ "SyntaxError"
    end

    test "it sends a message when the project has warnings " do
      {:ok, state} = with_project_state(:compilation_warnings)
      State.compile_project(state, true)

      assert_receive project_compiled(status: :success), 5000
      assert_receive project_diagnostics(diagnostics: diagnostics)

      assert [%Diagnostic{}, %Diagnostic{}] = diagnostics
    end
  end

  describe "initial_compile/1" do
    test "it works with a clean simple project" do
      {:ok, state} = with_project_state(:project_metadata)
      State.initial_compile(state)
    end

    test "it works with a clean umbrella project" do
      {:ok, state} = with_project_state(:project_metadata)
      State.initial_compile(state)
    end

    test "it works if the project has errors" do
      {:ok, state} = with_project_state(:parse_errors)
      State.initial_compile(state)
    end
  end

  describe "compiling source files" do
    setup [:with_metadata_project, :with_empty_module]

    test "handles syntax errors", %{state: state} do
      source = ~S[
        defmodule WithSyntaxErrors do
          def error do
            %{,}
          end
        end
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [diagnostic])

      assert %Diagnostic{} = diagnostic
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[syntax error before: ',']
      assert diagnostic.position == {4, 15}
    end

    test "handles missing token errors", %{state: state} do
      source = ~S[%{foo: 3]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [diagnostic])

      assert %Diagnostic{} = diagnostic
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[missing terminator: }]
      assert diagnostic.position == {1, 9}
    end

    test "handles compile errors", %{state: state} do
      source = ~S[
        doesnt_exist()
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [diagnostic])

      assert %Diagnostic{} = diagnostic
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[undefined function doesnt_exist/0]
      assert diagnostic.position == 2
    end

    test "handles function clause errors", %{state: state} do
      source = ~S[
        f = fn 1 -> :correct end
        f.(3)
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [diagnostic])

      assert %Diagnostic{} = diagnostic
      assert diagnostic.severity == :error
      assert diagnostic.message =~ "no function clause matching"
      assert diagnostic.position == 2
    end

    test "handles compile errors with suggestions", %{state: state} do
      source = ~S[

        IO.ins
      ]
      compile_source_file(state, "my_test.ex", source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic])
      assert diagnostic.severity == :error
      assert diagnostic.file =~ "my_test.ex"
      assert diagnostic.message =~ "function IO.ins/0 is undefined or private"
      assert diagnostic.position == {3, 12}
    end

    test "reports unused variables", %{state: state} do
      source = ~S[
        defmodule MissingVariable do
          def error do
            unused = 3
          end
        end
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :success)
      assert_receive file_diagnostics(diagnostics: [%Diagnostic{} = diagnostic])

      assert diagnostic.severity == :warning
      assert diagnostic.position == {4, 0}
      assert diagnostic.message =~ ~S["unused" is unused]
      assert diagnostic.details == {MissingVariable, :error, 0}
    end

    test "reports missing parens", %{state: state} do
      source = ~S[
        defmodule WithMissingParams do
          def error do
            calc
          end

          defp calc do
            3
          end
        end
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :success)
      assert_receive file_diagnostics(diagnostics: [%Diagnostic{} = diagnostic])

      assert diagnostic.severity == :warning
      assert diagnostic.position == {4, 0}

      assert diagnostic.message =~ ~S["calc" does not exist and is being expanded to "calc()"]

      assert diagnostic.details == {WithMissingParams, :error, 0}
    end

    test "reports unused defp functions", %{state: state} do
      source = ~S[
        defmodule UnusedDefp do
          defp unused do
          end
        end
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :success)
      assert_receive file_diagnostics(diagnostics: [%Diagnostic{} = diagnostic])

      assert diagnostic.severity == :warning
      assert diagnostic.position == {3, 0}
      assert diagnostic.message =~ ~S[function unused/0 is unused]
      assert diagnostic.details == nil
    end

    test "handles undefined usages", %{state: state} do
      source = ~S[
        defmodule WithUndefinedFunction do
          def error do
            unknown_fn()
          end
        end
      ]
      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [diagnostic])

      assert diagnostic.severity == :error
      assert diagnostic.position == 4
      assert diagnostic.message =~ ~S[undefined function unknown_fn/0]
      assert diagnostic.details == nil
    end

    test "reports multiple errors", %{state: state} do
      source = ~S[
        defmodule WithFiveErrors do
          def error(unused_1, unused_2) do
            unknown_fn()
            unused_3 = other_unknown()
          end
        end
      ]

      compile_source_file(state, source)

      assert_receive file_compiled(status: :error)
      assert_receive file_diagnostics(diagnostics: [_, _, _, _, _] = diagnostics), 5000

      assert length(diagnostics) == 5
    end
  end

  def with_a_valid_source_file(%{state: state}) do
    source = ~S[
      defmodule Testing.ValidSource do
        def add(a, b) do
          a + b
        end
      end
    ]

    source_file = source_file(state, source)
    {:ok, source_file: source_file}
  end

  describe "throttled compilation" do
    setup [:with_metadata_project, :with_a_valid_source_file]

    test "it doesn't compile immediately", %{state: state, source_file: source_file} do
      new_state =
        state
        |> State.on_file_compile(source_file)
        |> State.on_tick()

      assert State.compile_scheduled?(new_state, source_file.uri)
    end

    test "it compiles after a timeout", %{state: state, source_file: source_file} do
      state = State.on_file_compile(state, source_file)

      refute_eventually State.compile_scheduled?(State.on_tick(state), source_file.uri), 500
    end
  end
end
