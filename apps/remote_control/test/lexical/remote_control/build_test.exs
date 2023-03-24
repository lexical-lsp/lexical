defmodule Lexical.BuildTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.SourceFile
  alias Mix.Task.Compiler.Diagnostic

  import Messages
  import Lexical.Test.Fixtures
  use ExUnit.Case

  def compile_source_file(%Project{} = project, filename \\ "file.ex", source_code) do
    sequence = System.unique_integer([:monotonic, :positive])

    uri =
      project
      |> Project.root_path()
      |> Path.join(to_string(sequence))
      |> Path.join(filename)
      |> SourceFile.Path.to_uri()

    source = SourceFile.new(uri, source_code, 0)
    Build.compile_source_file(project, source)
  end

  def with_project(project_name) do
    project_name = to_string(project_name)
    fixture_dir = Path.join(fixtures_path(), project_name)
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    {:ok, project}
  end

  def with_empty_module(%{project: project}) do
    module = ~S[
      defmodule UnderTest do
        def test?, do: true
      end
    ]
    compile_source_file(project, module)
    assert_receive file_compiled(), 5000
    :ok
  end

  def with_metadata_project(_) do
    {:ok, project} = with_project(:project_metadata)
    {:ok, project: project}
  end

  def with_parse_errors_project(_) do
    {:ok, project} = with_project(:parse_errors)
    {:ok, project: project}
  end

  describe "compiling a project" do
    test "sends a message when complete " do
      {:ok, project} = with_project(:project_metadata)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :success), 5000
    end

    test "receives metadata about the defined modules" do
      {:ok, project} = with_project(:project_metadata)

      Build.schedule_compile(project, true)
      assert_receive module_updated(name: ProjectMetadata, functions: functions), 5000, 500

      assert {:zero_arity, 0} in functions
      assert {:one_arity, 1} in functions
      assert {:two_arity, 2} in functions
    end
  end

  describe "compiling an umbrella project" do
    test "it sends a message when compilation is complete" do
      {:ok, project} = with_project(:umbrella)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :success), 5000
      assert_receive project_diagnostics(diagnostics: [])

      assert_receive module_updated(name: Umbrella.First, functions: functions), 500

      assert {:arity_0, 0} in functions
      assert {:arity_1, 1} in functions
      assert {:arity_2, 2} in functions

      assert_receive module_updated(name: Umbrella.Second, functions: functions), 500, 500

      assert {:arity_0, 0} in functions
      assert {:arity_1, 1} in functions
      assert {:arity_2, 2} in functions
    end
  end

  describe "compiling a project that has errors" do
    test "it reports the errors" do
      {:ok, project} = with_project(:compilation_errors)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :error), 5000
      assert_receive project_diagnostics(diagnostics: [%Diagnostic{}])
    end
  end

  describe "compilng a project with parse errors" do
    setup :with_parse_errors_project

    test "stuff", %{project: project} do
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :error), 5000
      assert_receive project_diagnostics(diagnostics: [%Diagnostic{} = diagnostic])

      assert diagnostic.message =~ "SyntaxError"
    end
  end

  describe "when compiling a project that has warnings" do
    test "it reports them" do
      {:ok, project} = with_project(:compilation_warnings)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :success), 5000
      assert_receive project_diagnostics(diagnostics: diagnostics)

      assert [%Diagnostic{}, %Diagnostic{}] = diagnostics
    end
  end

  describe "project listener notifications" do
    setup [:with_metadata_project, :with_empty_module]

    test "adding a new module notifies the listener", %{project: project} do
      source = ~S[
      defmodule NewModule do
      end
      ]

      compile_source_file(project, source)
      assert_receive module_updated(name: NewModule, functions: []), 500
    end

    test "adding multiple modules notifies the listener for each module", %{project: project} do
      source = ~S[
        defmodule FirstModule do
        end

        defmodule SecondModule do
        end

        defmodule ThirdModule do
        end
      ]
      compile_source_file(project, source)

      assert_receive module_updated(name: FirstModule), 500, 500
      assert_receive module_updated(name: SecondModule), 500, 500
      assert_receive module_updated(name: ThirdModule), 500, 500
    end

    test "adding a function notifies the listener", %{project: project} do
      source = ~S[
        defmodule UnderTest do
          def added_function(a, b) do
            a + b
          end
        end
      ]

      compile_source_file(project, source)
      assert_receive module_updated(name: UnderTest, functions: [added_function: 2]), 500
    end

    test "removing a function notifies the listener", %{project: project} do
      initial = ~S[
      defmodule Remove do
        def remove_me do
        end
      end
      ]

      removed = ~S[
        defmodule Remove do
        end
      ]

      compile_source_file(project, initial)
      assert_receive module_updated(), 500

      compile_source_file(project, removed)
      assert_receive module_updated(name: Remove, functions: []), 500
    end

    test "changing a function's arity notifies the listener", %{project: project} do
      initial = ~S[
        defmodule ArityChange do
          def arity(_) do
          end
        end
      ]
      compile_source_file(project, initial)
      assert_receive module_updated(name: ArityChange, functions: [arity: 1]), 500

      changed = ~S[
        defmodule ArityChange do
          def arity(_, _) do
          end
        end
      ]
      compile_source_file(project, changed)
      assert_receive module_updated(name: ArityChange, functions: [arity: 2]), 500
    end

    test "adding a macro notifies the listener", %{project: project} do
      changed = ~S[
       defmodule UnderTest do
        defmacro something(a) do
          quote do
            a + 1
          end
        end
       end
      ]
      compile_source_file(project, changed)
      assert_receive module_updated(name: UnderTest, macros: [something: 1]), 500
    end

    test "removing a macro notifies the listener", %{project: project} do
      initial = ~S[
      defmodule RemoveMacro do
        defmacro remove_me do
        end
      end
      ]

      removed = ~S[
        defmodule RemoveMacro do
        end
      ]

      compile_source_file(project, initial)
      assert_receive module_updated(), 500

      compile_source_file(project, removed)
      assert_receive module_updated(name: RemoveMacro, macros: []), 500
    end

    test "changing a macro's arity notifies the listener", %{project: project} do
      initial = ~S[
        defmodule ArityChange do
          defmacro arity(_) do
          end
        end
      ]
      compile_source_file(project, initial)
      assert_receive module_updated(name: ArityChange, macros: [arity: 1]), 500

      changed = ~S[
        defmodule ArityChange do
          defmacro arity(_, _) do
          end
        end
      ]
      compile_source_file(project, changed)
      assert_receive module_updated(name: ArityChange, macros: [arity: 2]), 500
    end
  end

  describe "module sanitization" do
    setup [:with_metadata_project]

    test "adding an empty module doesn't add it to the project's code", %{project: project} do
      source = ~S[
        defmodule EmptyModule do
        end
      ]
      compile_source_file(project, source)
      assert_receive file_compiled(status: :success), 5000
      refute RemoteControl.call(project, Code, :ensure_loaded?, [EmptyModule])
    end

    test "a module that defines a function is kept", %{project: project} do
      source = ~S[
        defmodule WithAFunction do
          def has_function?, do: true
        end
      ]
      compile_source_file(project, source)
      assert_receive file_compiled(status: :success), 5000
      assert RemoteControl.call(project, Code, :ensure_loaded?, [WithAFunction])
    end

    test "a module that defines a macro is kept", %{project: project} do
      source = ~S[
        defmodule WithAMacro do
          defmacro has_macro?, do: true
        end
      ]
      compile_source_file(project, source)
      assert_receive file_compiled(status: :success), 5000
      assert RemoteControl.call(project, Code, :ensure_loaded?, [WithAMacro])
    end

    test "a module that defines a struct is kept", %{project: project} do
      source = ~S[
        defmodule WithAStruct do
          defstruct name: nil, value: nil
        end
      ]
      compile_source_file(project, source)
      assert_receive file_compiled(status: :success), 5000
      assert RemoteControl.call(project, Code, :ensure_loaded?, [WithAStruct])
    end

    test "a module with typespecs is kept", %{project: project} do
      source = ~S[
        defmodule WithAType do
          @type mod_type :: integer
        end
      ]
      compile_source_file(project, source)
      assert_receive file_compiled(status: :success), 5000
      assert RemoteControl.call(project, Code, :ensure_loaded?, [WithAType])
    end
  end
end
