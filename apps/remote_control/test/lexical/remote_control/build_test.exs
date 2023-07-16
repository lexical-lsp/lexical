defmodule Lexical.BuildTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.ProjectNodeSupervisor

  import Messages
  import Lexical.Test.Fixtures
  use ExUnit.Case
  use Patch

  def compile_document(%Project{} = project, file_path \\ nil, source_code) do
    uri =
      if is_binary(file_path) do
        Document.Path.to_uri(file_path)
      else
        sequence = System.unique_integer([:monotonic, :positive])

        project
        |> Project.root_path()
        |> Path.join(to_string(sequence))
        |> Path.join("file.exs")
        |> Document.Path.to_uri()
      end

    source = Document.new(uri, source_code, 0)
    Build.force_compile_document(project, source)
  end

  def with_project(project_name) do
    project_name = to_string(project_name)
    fixture_dir = Path.join(fixtures_path(), project_name)
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project, self())

    {:ok, project}
  end

  def with_empty_module(%{project: project}) do
    module = ~S[
      defmodule UnderTest do
        def test?, do: true
      end
    ]
    compile_document(project, module)
    assert_receive file_compiled(), 500
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

      assert_receive project_compiled(status: :success), 500
      assert_receive project_progress(label: "Building " <> project_name), 500
      assert project_name == "project_metadata"
    end

    test "receives metadata about the defined modules" do
      {:ok, project} = with_project(:project_metadata)

      Build.schedule_compile(project, true)
      assert_receive module_updated(name: ProjectMetadata, functions: functions), 500

      assert {:zero_arity, 0} in functions
      assert {:one_arity, 1} in functions
      assert {:two_arity, 2} in functions
    end
  end

  describe "compiling an umbrella project" do
    test "it sends a message when compilation is complete" do
      {:ok, project} = with_project(:umbrella)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :success), 500
      assert_receive project_diagnostics(diagnostics: []), 500

      assert_receive module_updated(name: Umbrella.First, functions: functions), 500

      assert {:arity_0, 0} in functions
      assert {:arity_1, 1} in functions
      assert {:arity_2, 2} in functions

      assert_receive module_updated(name: Umbrella.Second, functions: functions), 500

      assert {:arity_0, 0} in functions
      assert {:arity_1, 1} in functions
      assert {:arity_2, 2} in functions

      assert_receive project_progress(label: "Building " <> project_name), 500
      assert project_name == "umbrella"
    end
  end

  describe "compiling a project that has errors" do
    test "it reports the errors" do
      {:ok, project} = with_project(:compilation_errors)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :error), 500
      assert_receive project_diagnostics(diagnostics: [%Diagnostic.Result{}]), 500
    end
  end

  describe "compilng a project with parse errors" do
    setup :with_parse_errors_project

    test "stuff", %{project: project} do
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :error), 500
      assert_receive project_diagnostics(diagnostics: [%Diagnostic.Result{} = diagnostic]), 500

      assert diagnostic.uri
      assert diagnostic.message =~ "SyntaxError"
    end
  end

  describe "when compiling a project that has warnings" do
    test "it reports them" do
      {:ok, project} = with_project(:compilation_warnings)
      Build.schedule_compile(project, true)

      assert_receive project_compiled(status: :success), 500
      assert_receive project_diagnostics(diagnostics: diagnostics), 500

      assert [%Diagnostic.Result{}, %Diagnostic.Result{}] = diagnostics

      for diagnostic <- diagnostics do
        assert diagnostic.uri
      end
    end
  end

  def with_patched_state_timeout(_) do
    patch(Lexical.RemoteControl.Build.State, :should_compile?, true)
    patch(Lexical.RemoteControl.Build.State, :edit_window_millis, 50)
    :ok
  end

  describe "compiling source files" do
    setup [:with_metadata_project, :with_empty_module, :with_patched_state_timeout]

    test "handles syntax errors", %{project: project} do
      source = ~S[
        defmodule WithErrors do
          def error do
            %{,}
          end
        end
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500

      assert %Diagnostic.Result{} = diagnostic
      assert diagnostic.uri
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[syntax error before: ',']
      assert diagnostic.position == {4, 15}
    end

    test "handles missing token errors", %{project: project} do
      source = ~S[%{foo: 3]
      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500

      assert %Diagnostic.Result{} = diagnostic
      assert diagnostic.uri
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[missing terminator: }]
      assert diagnostic.position == {1, 9}
    end

    test "handles compile errors", %{project: project} do
      source = ~S[
        doesnt_exist()
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500

      assert %Diagnostic.Result{} = diagnostic
      assert diagnostic.uri
      assert diagnostic.severity == :error
      assert diagnostic.message =~ ~S[undefined function doesnt_exist/0]

      if version_after_1_15?() do
        assert diagnostic.position == {2, 9}
      else
        assert diagnostic.position == 2
      end
    end

    test "handles function clause errors", %{project: project} do
      source = ~S[
        f = fn 1 -> :correct end
        f.(3)
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500

      assert %Diagnostic.Result{} = diagnostic
      assert diagnostic.uri
      assert diagnostic.severity == :error
      assert diagnostic.message =~ "no function clause matching"
      assert diagnostic.position == 2
    end

    test "handles compile errors with suggestions", %{project: project} do
      source = ~S[

        IO.ins
      ]
      compile_document(project, "my_test.ex", source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500
      assert diagnostic.severity == :error
      assert diagnostic.uri =~ "my_test.ex"
      assert diagnostic.message =~ "function IO.ins/0 is undefined or private"
      assert diagnostic.position == {3, 12}
    end

    test "reports unused variables", %{project: project} do
      source = ~S[
        defmodule WithWarnings do
          def error do
            unused = 3
          end
        end
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :success), 500
      assert_receive file_diagnostics(diagnostics: [%Diagnostic.Result{} = diagnostic]), 500

      assert diagnostic.uri
      assert diagnostic.severity == :warning
      assert diagnostic.message =~ ~S[variable "unused" is unused]

      if version_after_1_15?() do
        assert diagnostic.position == {4, 13}
      else
        assert diagnostic.details == {WithWarnings, :error, 0}
        assert diagnostic.position == 4
      end
    end

    test "reports missing parens", %{project: project} do
      source = ~S[
        defmodule WithWarnings do
          def error do
            calc
          end

          defp calc do
            3
          end
        end
      ]
      compile_document(project, source)

      assert_receive file_diagnostics(diagnostics: [%Diagnostic.Result{} = diagnostic | _]), 500
      assert diagnostic.uri

      if version_after_1_15?() do
        assert diagnostic.severity == :error

        assert diagnostic.message =~
                 ~s[undefined variable "calc"]

        assert diagnostic.position == {4, 13}
      else
        assert_receive file_compiled(status: :success), 500
        assert diagnostic.severity == :warning
        assert diagnostic.details == {WithWarnings, :error, 0}
        assert diagnostic.position == 4

        assert diagnostic.message =~
                 ~S[warning: variable "calc" does not exist and is being expanded to "calc()"]
      end
    end

    test "reports unused defp functions", %{project: project} do
      source = ~S[
        defmodule UnusedDefp do
          defp unused do
          end
        end
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :success), 500
      assert_receive file_diagnostics(diagnostics: [%Diagnostic.Result{} = diagnostic]), 500

      assert diagnostic.uri
      assert diagnostic.severity == :warning
      assert diagnostic.position == 3
      assert diagnostic.message =~ ~S[function unused/0 is unused]
      assert diagnostic.details == nil
    end

    test "handles undefined usages", %{project: project} do
      source = ~S[
        defmodule WithUndefinedFunction do
          def error do
            unknown_fn()
          end
        end
      ]
      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500
      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500

      assert diagnostic.uri
      assert diagnostic.severity == :error
      assert diagnostic.position == 4
      assert diagnostic.message =~ ~S[undefined function unknown_fn/0]
      assert diagnostic.details == nil
    end

    test "reports multiple errors", %{project: project} do
      source = ~S[
        defmodule WithFiveErrors do
          def error(unused_1, unused_2) do
            unknown_fn()
            unused_3 = other_unknown()
          end
        end
      ]

      compile_document(project, source)

      assert_receive file_compiled(status: :error), 500

      if version_after_1_15?() do
        assert_receive file_diagnostics(diagnostics: [_, _, _] = diagnostics), 500
        assert length(diagnostics) == 3
      else
        assert_receive file_diagnostics(diagnostics: [_, _, _, _, _] = diagnostics), 500
        assert length(diagnostics) == 5
      end
    end

    test "adding a new module notifies the listener", %{project: project} do
      source = ~S[
      defmodule NewModule do
      end
      ]

      compile_document(project, source)
      assert_receive module_updated(name: NewModule, functions: []), 500
    end

    test "adding a non-loaded module notifies the listener", %{project: project} do
      source = ~S[
      defmodule NotLoaded do
        @compile {:autoload, false}
        defstruct loaded: false
      end
      ]
      compile_document(project, source)

      assert_receive module_updated(name: NotLoaded, struct: fields), 500
      assert [%{field: :loaded, required?: true}] = fields
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
      compile_document(project, source)

      assert_receive module_updated(name: FirstModule), 500
      assert_receive module_updated(name: SecondModule), 500
      assert_receive module_updated(name: ThirdModule), 500
    end

    test "adding a function notifies the listener", %{project: project} do
      source = ~S[
        defmodule UnderTest do
          def added_function(a, b) do
            a + b
          end
        end
      ]

      compile_document(project, source)
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

      compile_document(project, initial)
      assert_receive module_updated(), 500

      compile_document(project, removed)
      assert_receive module_updated(name: Remove, functions: []), 500
    end

    test "changing a function's arity notifies the listener", %{project: project} do
      initial = ~S[
        defmodule ArityChange do
          def arity(_) do
          end
        end
      ]
      compile_document(project, initial)
      assert_receive module_updated(name: ArityChange, functions: [arity: 1]), 500

      changed = ~S[
        defmodule ArityChange do
          def arity(_, _) do
          end
        end
      ]
      compile_document(project, changed)
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
      compile_document(project, changed)
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

      compile_document(project, initial)
      assert_receive module_updated(), 500

      compile_document(project, removed)
      assert_receive module_updated(name: RemoveMacro, macros: []), 500
    end

    test "changing a macro's arity notifies the listener", %{project: project} do
      initial = ~S[
        defmodule ArityChange do
          defmacro arity(_) do
          end
        end
      ]
      compile_document(project, initial)
      assert_receive module_updated(name: ArityChange, macros: [arity: 1]), 500

      changed = ~S[
        defmodule ArityChange do
          defmacro arity(_, _) do
          end
        end
      ]
      compile_document(project, changed)
      assert_receive module_updated(name: ArityChange, macros: [arity: 2]), 500
    end
  end

  describe "app config" do
    setup [:with_metadata_project]

    test "allows config to be read", %{project: project} do
      initial = ~S[
        defmodule WithConfig do
          @date_module Application.compile_env(:project_metadata, :date_module)
          @date_module.utc_today()
        end
      ]

      compile_document(project, initial)
      assert_receive file_compile_requested(uri: file_uri), 500
      assert_receive file_diagnostics(uri: ^file_uri, diagnostics: []), 500
    end
  end

  def loaded?(project, module) do
    RemoteControl.call(project, Code, :ensure_loaded?, [module])
  end

  describe "module sanitization" do
    setup [:with_metadata_project]

    test "editing a module clears intermediate modules", %{project: project} do
      source = ~S[
        defmodule Module.<edit>.Submodule do
          def my_fun do
          end
        end
      ]

      for submodule <- ~w(S Su Sub),
          source = String.replace(source, "<edit>", submodule),
          module_name = Module.concat(["Module", submodule, "Submodule"]) do
        compile_document(project, __ENV__.file, source)

        assert_receive module_updated(name: ^module_name), 500
      end

      refute loaded?(project, Module.S.Submodule)
      refute loaded?(project, Module.Su.Submodule)
      assert loaded?(project, Module.Sub.Submodule)
    end

    test "empty modules are kept", %{project: project} do
      source = ~S[
        defmodule EmptyModule do
        end
      ]
      compile_document(project, source)
      assert_receive file_compiled(status: :success), 500
      assert loaded?(project, EmptyModule)
    end

    test "a module that defines a function is kept", %{project: project} do
      source = ~S[
        defmodule WithAFunction do
          def has_function?, do: true
        end
      ]
      compile_document(project, source)
      assert_receive file_compiled(status: :success), 500
      assert loaded?(project, WithAFunction)
    end

    test "a module that defines a macro is kept", %{project: project} do
      source = ~S[
        defmodule WithAMacro do
          defmacro has_macro?, do: true
        end
      ]
      compile_document(project, source)
      assert_receive file_compiled(status: :success), 500
      assert loaded?(project, WithAMacro)
    end

    test "a module that defines a struct is kept", %{project: project} do
      source = ~S[
        defmodule WithAStruct do
          defstruct name: nil, value: nil
        end
      ]
      compile_document(project, source)
      assert_receive file_compiled(status: :success), 500
      assert loaded?(project, WithAStruct)
    end

    test "a module with typespecs is kept", %{project: project} do
      source = ~S[
        defmodule WithAType do
          @type mod_type :: integer
        end
      ]
      compile_document(project, source)
      assert_receive file_compiled(status: :success), 500
      assert loaded?(project, WithAType)
    end
  end

  defp version_after_1_15? do
    Version.match?(System.version(), "~> 1.15")
  end
end
