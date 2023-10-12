defmodule Lexical.Server.CodeIntelligence.EntityTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ProjectNodeSupervisor
  alias Lexical.Server.CodeIntelligence.Entity

  import Lexical.Document.Line
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures
  import Lexical.Test.RangeSupport

  use ExUnit.Case, async: false

  defp with_referenced_file(%{project: project}) do
    uri =
      project
      |> file_path(Path.join("lib", "my_definition.ex"))
      |> Document.Path.ensure_uri()

    %{uri: uri}
  end

  defp subject_module_uri(project) do
    project
    |> file_path(Path.join("lib", "my_module.ex"))
    |> Document.Path.ensure_uri()
  end

  defp subject_module(project, content) do
    uri = subject_module_uri(project)

    with :ok <- Document.Store.open(uri, content, 1) do
      Document.Store.fetch(uri)
    end
  end

  setup_all do
    start_supervised!(Lexical.Document.Store)

    project = project(:navigations)
    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project)

    RemoteControl.Api.register_listener(project, self(), [:all])
    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000

    %{project: project}
  end

  setup %{project: project} do
    uri = subject_module_uri(project)

    # NOTE: We need to make sure every tests start with fresh caller content file
    on_exit(fn ->
      :ok = Document.Store.close(uri)
    end)
  end

  describe "definition/2 when making remote call by alias" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition.greet|("World")
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of the module", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_greet() do
            MyDefinition|.greet("World")
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[defmodule «MyDefinition» do]
    end

    test "find the macro definition", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MyDefinition

          def uses_macro() do
            MyDefinition.print_hello|()
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end

    @doc """
    This is a limitation of the ElixirSense.
    It doesn't support finding the multiple arity definition when making remote call
    currently, it will always return the first definition.

    ## Example

      iex> defmodule MultiArity do
      ...>   def sum(a, b) do
      ...>     a + b
      ...>   end
      ...>
      ...>   def sum(a, b, c) do
      ...>     a + b + c
      ...>   end
      ...> end

    When we want to jump to the definition of `MultiArity.sum/3`,
    we will always go to the `MultiArity.sum/2`
    """
    @tag :skip
    test "find the right arity function definition", %{project: project} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          alias MultiArity

          def uses_multiple_arity_fun() do
            MultiArity.sum|(1, 2, 3)
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line == ~S[  def «sum»(a, b, c) do]
      assert referenced_uri =~ "navigations/lib/multi_arity.ex"
    end
  end

  describe "definition/2 when making remote call by import" do
    setup [:with_referenced_file]

    test "find the definition of a remote function call", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    test "find the definition of a remote macro call",
         %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          import MyDefinition

          def uses_macro() do
            print_hello|()
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  defmacro «print_hello» do]
    end
  end

  describe "definition/2 when making remote call by use to import definition" do
    setup [:with_referenced_file]

    test "find the function definition", %{project: project, uri: referenced_uri} do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_greet() do
            greet|("World")
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «greet»(name) do]
    end

    @doc """
    This is a limitation of the ElixirSense.
    like the `subject_module` below, it can't find the correct definition of `hello_func_in_using/0`
    when the definition module aliased by `use` or `import`,
    currently, it will go to the `use MyDefinition` line
    """
    @tag :skip
    test "find the correct definition when func defined in the quote block", %{
      project: project,
      uri: referenced_uri
    } do
      subject_module = ~q[
        defmodule UsesRemoteFunction do
          use MyDefinition

          def uses_hello_defined_in_using_quote() do
            hello_func_in_using|()
          end
        end
      ]

      assert {:ok, ^referenced_uri, definition_line} = definition(project, subject_module)
      assert definition_line == ~S[  def «hello_func_in_using» do]
    end
  end

  describe "definition/2 when making local call" do
    test "find the function definition", %{project: project} do
      subject_module = ~q[
        defmodule UsesOwnFunction do
          def greet do
          end

          def uses_greet do
            greet|()
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line == ~S[  def «greet» do]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the attribute", %{project: project} do
      subject_module = ~q[
        defmodule UsesAttribute do
          @b 2

          def use_attribute do
            @|b
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line =~ ~S[«@b» 2]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    test "find the variable", %{project: project} do
      subject_module = ~q[
        defmodule UsesVariable do
          def use_variable do
            a = 1

            if true do
              a|
            end
          end
        end
      ]

      {:ok, referenced_uri, definition_line} = definition(project, subject_module)

      assert definition_line =~ ~S[«a» = 1]
      assert referenced_uri =~ "navigations/lib/my_module.ex"
    end

    @doc """
    This is a limitation of the ElixirSense.
    like the `subject_module` below, it can't find the correct definition of `String.to_integer/1`,
    currently, it will always return `{:ok, nil}`
    """
    @tag :skip
    test "find the definition when calling a Elixir std module function",
         %{project: project} do
      subject_module = ~q[
        String.to_integer|("1")
      ]

      {:ok, uri, definition_line} = definition(project, subject_module)

      assert uri =~ "lib/elixir/lib/string.ex"
      assert definition_line =~ ~S[  def «to_integer»(string) when is_binary(string) do]
    end

    test "find the definition when calling a erlang module", %{project: project} do
      subject_module = ~q[
        :erlang.binary_to_atom|("1")
      ]

      {:ok, uri, definition_line} = definition(project, subject_module)

      assert uri =~ "/src/erlang.erl"
      assert definition_line =~ ~S[«binary_to_atom»(Binary)]
    end
  end

  describe "references/2 for modules" do
    setup [:with_referenced_file]

    test "finds all references for a plain module", %{project: project} do
      subject_module = ~q[
        defmodule SomeModule do
          alias MyDefinition|

        end
      ]
      {:ok, _, locations} = references(project, subject_module)
      assert length(locations) > 0

      Enum.each(locations, fn %Location{} = location ->
        line(text: text) = location.range.start.context_line
        assert text =~ "MyDefinition"
      end)
    end

    test "finds references for an aliased module", %{project: project} do
      subject_module = ~q[
        defmodule Subject do
        alias MyDefinition, as: Def
          def func do
            Def|
          end
        end
      ]

      {:ok, _, locations} = references(project, subject_module)
      assert length(locations) > 0

      Enum.each(locations, fn %Location{} = location ->
        line(text: text) = location.range.start.context_line
        assert text =~ "MyDefinition"
      end)
    end
  end

  describe "module resolve/2" do
    test "succeeds with trailing period", %{project: project} do
      code = ~q[
        Some.Modul|e.
      ]

      assert {:ok, {:module, Some.Module}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«Some.Module».]
    end

    test "succeeds immediately following the module", %{project: project} do
      code = ~q[
        Beyond.The.End|
      ]

      assert {:ok, {:module, Beyond.The.End}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«Beyond.The.End»]
    end

    test "fails with an extra space following the module", %{project: project} do
      code = ~q[
        Beyond.The.End |
      ]

      assert {:error, :not_found} = resolve(project, code)
    end

    test "fails immediately preceeding the module", %{project: project} do
      code = ~q[
        | Before.The.Beginning
      ]

      assert {:error, :not_found} = resolve(project, code)
    end

    test "resolves module segments at and before the cursor", %{project: project} do
      code = ~q[
        In.|The.Middle
      ]

      assert {:ok, {:module, In.The}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«In.The».Middle]
    end

    test "excludes trailing module segments with the cursor is on a period", %{project: project} do
      code = ~q[
        AAA.BBB.CCC.DDD|.EEE
      ]

      assert {:ok, {:module, AAA.BBB.CCC.DDD}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«AAA.BBB.CCC.DDD».EEE]
    end

    test "succeeds for modules within a multi-line node", %{project: project} do
      code = ~q[
        foo =
          On.Another.Lin|e
      ]

      assert {:ok, {:module, On.Another.Line}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «On.Another.Line»]
    end

    test "resolves the entire module for multi-line modules", %{project: project} do
      code = ~q[
        On.
          |Multiple.
          Lines
      ]

      assert {:ok, {:module, On.Multiple.Lines}, resolved_range} = resolve(project, code)

      assert resolved_range =~ """
             «On.
               Multiple.
               Lines»\
             """
    end

    test "succeeds in single line calls", %{project: project} do
      code = ~q[
        |Enum.map(1..10, & &1 + 1)
      ]

      assert {:ok, {:module, Enum}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«Enum».map(1..10, & &1 + 1)]
    end

    test "succeeds in multi-line calls", %{project: project} do
      code = ~q[
        |Enum.map(1..10, fn i ->
          i + 1
        end)
      ]

      assert {:ok, {:module, Enum}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«Enum».map(1..10, fn i ->]
    end

    test "expands top-level aliases", %{project: project} do
      code = ~q[
        defmodule Example do
          alias Long.Aliased.Module
          Modul|e
        end
      ]

      assert {:ok, {:module, Long.Aliased.Module}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «Module»]
    end

    test "ignores top-level aliases made after the cursor", %{project: project} do
      code = ~q[
        defmodule Example do
          Modul|e
          alias Long.Aliased.Module
        end
      ]

      assert {:ok, {:module, Module}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «Module»]
    end

    test "resolves implicit aliases", %{project: project} do
      code = ~q[
        defmodule Example do
          defmodule Inner do
          end

          Inne|r
        end
      ]

      assert {:ok, {:module, Example.Inner}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «Inner»]
    end

    test "expands current module", %{project: project} do
      code = ~q[
        defmodule Example do
          |__MODULE__
        end
      ]

      assert {:ok, {:module, Example}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «__MODULE__»]
    end

    test "expands current module used in alias", %{project: project} do
      code = ~q[
        defmodule Example do
          |__MODULE__.Nested
        end
      ]

      assert {:ok, {:module, Example}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «__MODULE__».Nested]
    end

    test "expands alias following current module", %{project: project} do
      code = ~q[
        defmodule Example do
          __MODULE__.|Nested
        end
      ]

      assert {:ok, {:module, Example.Nested}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «__MODULE__.Nested»]
    end
  end

  describe "struct resolve/2" do
    test "succeeds when the cursor is on the %", %{project: project} do
      code = ~q[
        |%MyStruct{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the cursor is in an alias", %{project: project} do
      code = ~q[
        %My|Struct{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the cursor is on the opening bracket", %{project: project} do
      code = ~q[
        %MyStruct|{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the struct fields span multiple lines", %{project: project} do
      code = ~q[
        %MyStruct.|Nested{
          foo: 1,
          bar: 2
        }
      ]

      assert {:ok, {:struct, MyStruct.Nested}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[%«MyStruct.Nested»{]
    end

    test "succeeds when the struct spans multiple lines", %{project: project} do
      code = ~q[
        %On.
          |Multiple.
          Lines{}
      ]

      assert {:ok, {:struct, On.Multiple.Lines}, resolved_range} = resolve(project, code)

      assert resolved_range =~ """
             %«On.
               Multiple.
               Lines»{}\
             """
    end

    test "includes trailing module segments", %{project: project} do
      code = ~q[
        %My|Struct.Nested{}
      ]

      assert {:ok, {:struct, MyStruct.Nested}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[%«MyStruct.Nested»{}]
    end

    test "expands current module", %{project: project} do
      code = ~q[
        defmodule Example do
          %|__MODULE__{}
        end
      ]

      assert {:ok, {:struct, Example}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  %«__MODULE__»{}]
    end

    test "succeeds for implicitly aliased module", %{project: project} do
      code = ~q<
        defmodule Example do
          defmodule Inner do
            defstruct []
          end

          %|Inner{}
        end
      >

      assert {:ok, {:struct, Example.Inner}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  %«Inner»{}]
    end

    test "succeeds for explicitly aliased module", %{project: project} do
      code = ~q[
        defmodule Example do
          alias Something.Example
          %Example.|Inner{}
        end
      ]

      assert {:ok, {:struct, Something.Example.Inner}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  %«Example.Inner»{}]
    end

    test "succeeds for module nested inside current module", %{project: project} do
      code = ~q[
        defmodule Example do
          %__MODULE__.|Inner{}
        end
      ]

      assert {:ok, {:struct, Example.Inner}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  %«__MODULE__.Inner»{}]
    end
  end

  describe "call resolve/2" do
    test "qualified call", %{project: project} do
      code = ~q[
        def example do
          MyModule.|some_function(1, 2, 3)
        end
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«MyModule.some_function»(1, 2, 3)]
    end

    test "qualified call without parens", %{project: project} do
      code = ~q[
        MyModule.|some_function 1, 2, 3
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«MyModule.some_function» 1, 2, 3]
    end

    test "qualified call with nested alias", %{project: project} do
      code = ~q[
        MyModule.Nested.|some_function(1, 2, 3)
      ]

      assert {:ok, {:call, MyModule.Nested, :some_function, 3}, resolved_range} =
               resolve(project, code)

      assert resolved_range =~ ~S[«MyModule.Nested.some_function»(1, 2, 3)]
    end

    test "multi-line qualified call", %{project: project} do
      code = ~q[
        MyModule.|some_function(
          1, 2, 3
        )
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[«MyModule.some_function»(]
    end

    test "qualified call at start of pipe", %{project: project} do
      code = ~q[
        1
        |> MyModule.|some_function(2, 3)
        |> other()
        |> other()
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call at end of pipe", %{project: project} do
      code = ~q[
        1
        |> other()
        |> other()
        |> MyModule.|some_function(2, 3)
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call nested in a pipe", %{project: project} do
      code = ~q[
        1
        |> other()
        |> MyModule.|some_function(2, 3)
        |> other()
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call inside another call", %{project: project} do
      code = ~q[
        foo(1, 2, MyModule.|some_function(3))
      ]

      assert {:ok, {:call, MyModule, :some_function, 1}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[foo(1, 2, «MyModule.some_function»(3))]
    end

    test "qualified call on same line as a string with newlines", %{project: project} do
      code = ~q[
        Enum.map_join(list, "\n\n---\n\n", &String.tri|m(&1)) <> "\n"
      ]

      assert {:ok, {:call, String, :trim, 1}, _} = resolve(project, code)
    end

    test "qualified call within a block", %{project: project} do
      code = ~q/
        if true do
          MyModule.some_|function(bar)
          :ok
        end
      /

      assert {:ok, {:call, MyModule, :some_function, 1}, _} = resolve(project, code)
    end

    test "qualified call on left of type operator", %{project: project} do
      code = ~q[
        my_dsl do
          MyModule.|my_fun() :: MyModule.t()
        end
      ]

      assert {:ok, {:call, MyModule, :my_fun, 0}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  «MyModule.my_fun»() :: MyModule.t()]
    end
  end

  describe "type resolve/2" do
    test "qualified types in @type", %{project: project} do
      code = ~q[
        @type my_type :: MyModule.|t()
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[@type my_type :: «MyModule.t»()]
    end

    test "qualified types in @spec", %{project: project} do
      code = ~q[
        @spec my_fun() :: MyModule.|t()
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[@spec my_fun() :: «MyModule.t»()]
    end

    test "qualified types in DSL", %{project: project} do
      code = ~q[
        my_dsl do
          my_fun() :: MyModule.|t()
        end
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[  my_fun() :: «MyModule.t»()]
    end

    test "qualified types in nested structure", %{project: project} do
      code = ~q[
        @type my_type :: %{foo: MyModule.|t()}
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(project, code)
      assert resolved_range =~ ~S[@type my_type :: %{foo: «MyModule.t»()}]
    end
  end

  defp resolve(project, code) do
    with {position, code} <- pop_cursor(code),
         {:ok, document} <- subject_module(project, code),
         {:ok, resolved, range} <- Entity.resolve(document, position) do
      {:ok, resolved, decorate(document, range)}
    end
  end

  defp definition(project, code) do
    with {position, code} <- pop_cursor(code),
         {:ok, document} <- subject_module(project, code),
         {:ok, %Location{} = location} <-
           Entity.definition(project, document, position) do
      {:ok, location.document.uri, decorate(location.document, location.range)}
    end
  end

  defp references(project, code) do
    with {position, code} <- pop_cursor(code),
         {:ok, document} <- subject_module(project, code),
         {:ok, locations} <- Entity.references(project, document, position) do
      {:ok, document, locations}
    end
  end
end
