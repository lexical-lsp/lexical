defmodule Lexical.RemoteControl.CodeIntelligence.EntityTest do
  alias Lexical.Document
  alias Lexical.RemoteControl.CodeIntelligence.Entity

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures
  import Lexical.Test.RangeSupport

  use ExUnit.Case, async: true

  describe "module resolve/2" do
    test "succeeds with trailing period" do
      code = ~q[
        Some.Modul|e.
      ]

      assert {:ok, {:module, Some.Module}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«Some.Module».]
    end

    test "succeeds immediately following the module" do
      code = ~q[
        Beyond.The.End|
      ]

      assert {:ok, {:module, Beyond.The.End}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«Beyond.The.End»]
    end

    test "fails with an extra space following the module" do
      code = ~q[
        Beyond.The.End |
      ]

      assert {:error, :not_found} = resolve(code)
    end

    test "fails immediately preceeding the module" do
      code = ~q[
        | Before.The.Beginning
      ]

      assert {:error, :not_found} = resolve(code)
    end

    test "resolves module segments at and before the cursor" do
      code = ~q[
        In.|The.Middle
      ]

      assert {:ok, {:module, In.The}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«In.The».Middle]
    end

    test "excludes trailing module segments with the cursor is on a period" do
      code = ~q[
        AAA.BBB.CCC.DDD|.EEE
      ]

      assert {:ok, {:module, AAA.BBB.CCC.DDD}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«AAA.BBB.CCC.DDD».EEE]
    end

    test "succeeds for modules within a multi-line node" do
      code = ~q[
        foo =
          On.Another.Lin|e
      ]

      assert {:ok, {:module, On.Another.Line}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «On.Another.Line»]
    end

    test "resolves the entire module for multi-line modules" do
      code = ~q[
        On.
          |Multiple.
          Lines
      ]

      assert {:ok, {:module, On.Multiple.Lines}, resolved_range} = resolve(code)

      assert resolved_range =~ """
             «On.
               Multiple.
               Lines»\
             """
    end

    test "succeeds in single line calls" do
      code = ~q[
        |Enum.map(1..10, & &1 + 1)
      ]

      assert {:ok, {:module, Enum}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«Enum».map(1..10, & &1 + 1)]
    end

    test "succeeds in multi-line calls" do
      code = ~q[
        |Enum.map(1..10, fn i ->
          i + 1
        end)
      ]

      assert {:ok, {:module, Enum}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«Enum».map(1..10, fn i ->]
    end

    test "expands top-level aliases" do
      code = ~q[
        defmodule Example do
          alias Long.Aliased.Module
          Modul|e
        end
      ]

      assert {:ok, {:module, Long.Aliased.Module}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «Module»]
    end

    test "ignores top-level aliases made after the cursor" do
      code = ~q[
        defmodule Example do
          Modul|e
          alias Long.Aliased.Module
        end
      ]

      assert {:ok, {:module, Module}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «Module»]
    end

    test "resolves implicit aliases" do
      code = ~q[
        defmodule Example do
          defmodule Inner do
          end

          Inne|r
        end
      ]

      assert {:ok, {:module, Example.Inner}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «Inner»]
    end

    test "expands current module" do
      code = ~q[
        defmodule Example do
          |__MODULE__
        end
      ]

      assert {:ok, {:module, Example}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «__MODULE__»]
    end

    test "expands current module used in alias" do
      code = ~q[
        defmodule Example do
          |__MODULE__.Nested
        end
      ]

      assert {:ok, {:module, Example}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «__MODULE__».Nested]
    end

    test "expands alias following current module" do
      code = ~q[
        defmodule Example do
          __MODULE__.|Nested
        end
      ]

      assert {:ok, {:module, Example.Nested}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «__MODULE__.Nested»]
    end
  end

  describe "struct resolve/2" do
    test "succeeds when the cursor is on the %" do
      code = ~q[
        |%MyStruct{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the cursor is in an alias" do
      code = ~q[
        %My|Struct{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the cursor is on the opening bracket" do
      code = ~q[
        %MyStruct|{}
      ]

      assert {:ok, {:struct, MyStruct}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[%«MyStruct»{}]
    end

    test "succeeds when the struct fields span multiple lines" do
      code = ~q[
        %MyStruct.|Nested{
          foo: 1,
          bar: 2
        }
      ]

      assert {:ok, {:struct, MyStruct.Nested}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[%«MyStruct.Nested»{]
    end

    test "succeeds when the struct spans multiple lines" do
      code = ~q[
        %On.
          |Multiple.
          Lines{}
      ]

      assert {:ok, {:module, On.Multiple.Lines}, resolved_range} = resolve(code)

      assert resolved_range =~ """
             %«On.
               Multiple.
               Lines»{}\
             """
    end

    test "shouldn't include trailing module segments" do
      code = ~q[
        %My|Struct.Nested{}
      ]

      assert {:ok, {:module, MyStruct}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[%«MyStruct».Nested{}]
    end

    test "expands current module" do
      code = ~q[
        defmodule Example do
          %|__MODULE__{}
        end
      ]

      assert {:ok, {:struct, Example}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  %«__MODULE__»{}]
    end

    test "succeeds for implicitly aliased module" do
      code = ~q<
        defmodule Example do
          defmodule Inner do
            defstruct []
          end

          %|Inner{}
        end
      >

      assert {:ok, {:struct, Example.Inner}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  %«Inner»{}]
    end

    test "succeeds for explicitly aliased module" do
      code = ~q[
        defmodule Example do
          alias Something.Example
          %Example.|Inner{}
        end
      ]

      assert {:ok, {:struct, Something.Example.Inner}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  %«Example.Inner»{}]
    end

    test "succeeds for module nested inside current module" do
      code = ~q[
        defmodule Example do
          %__MODULE__.|Inner{}
        end
      ]

      assert {:ok, {:struct, Example.Inner}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  %«__MODULE__.Inner»{}]
    end
  end

  describe "call resolve/2" do
    test "qualified call" do
      code = ~q[
        def example do
          MyModule.|some_function(1, 2, 3)
        end
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«MyModule.some_function»(1, 2, 3)]
    end

    test "qualified call without parens" do
      code = ~q[
        MyModule.|some_function 1, 2, 3
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«MyModule.some_function» 1, 2, 3]
    end

    test "qualified call with nested alias" do
      code = ~q[
        MyModule.Nested.|some_function(1, 2, 3)
      ]

      assert {:ok, {:call, MyModule.Nested, :some_function, 3}, resolved_range} = resolve(code)

      assert resolved_range =~ ~S[«MyModule.Nested.some_function»(1, 2, 3)]
    end

    test "multi-line qualified call" do
      code = ~q[
        MyModule.|some_function(
          1, 2, 3
        )
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[«MyModule.some_function»(]
    end

    test "qualified call at start of pipe" do
      code = ~q[
        1
        |> MyModule.|some_function(2, 3)
        |> other()
        |> other()
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call at end of pipe" do
      code = ~q[
        1
        |> other()
        |> other()
        |> MyModule.|some_function(2, 3)
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call nested in a pipe" do
      code = ~q[
        1
        |> other()
        |> MyModule.|some_function(2, 3)
        |> other()
      ]

      assert {:ok, {:call, MyModule, :some_function, 3}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[|> «MyModule.some_function»(2, 3)]
    end

    test "qualified call inside another call" do
      code = ~q[
        foo(1, 2, MyModule.|some_function(3))
      ]

      assert {:ok, {:call, MyModule, :some_function, 1}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[foo(1, 2, «MyModule.some_function»(3))]
    end

    test "qualified call on same line as a string with newlines" do
      code = ~q[
        Enum.map_join(list, "\n\n---\n\n", &String.tri|m(&1)) <> "\n"
      ]

      assert {:ok, {:call, String, :trim, 1}, _} = resolve(code)
    end

    test "qualified call within a block" do
      code = ~q/
        if true do
          MyModule.some_|function(bar)
          :ok
        end
      /

      assert {:ok, {:call, MyModule, :some_function, 1}, _} = resolve(code)
    end

    test "qualified call on left of type operator" do
      code = ~q[
        my_dsl do
          MyModule.|my_fun() :: MyModule.t()
        end
      ]

      assert {:ok, {:call, MyModule, :my_fun, 0}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  «MyModule.my_fun»() :: MyModule.t()]
    end
  end

  describe "type resolve/2" do
    test "qualified types in @type" do
      code = ~q[
        @type my_type :: MyModule.|t()
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[@type my_type :: «MyModule.t»()]
    end

    test "qualified types in @spec" do
      code = ~q[
        @spec my_fun() :: MyModule.|t()
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[@spec my_fun() :: «MyModule.t»()]
    end

    test "qualified types in DSL" do
      code = ~q[
        my_dsl do
          my_fun() :: MyModule.|t()
        end
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[  my_fun() :: «MyModule.t»()]
    end

    test "qualified types in nested structure" do
      code = ~q[
        @type my_type :: %{foo: MyModule.|t()}
      ]

      assert {:ok, {:type, MyModule, :t, 0}, resolved_range} = resolve(code)
      assert resolved_range =~ ~S[@type my_type :: %{foo: «MyModule.t»()}]
    end
  end

  defp subject_module_uri do
    project()
    |> file_path(Path.join("lib", "my_module.ex"))
    |> Document.Path.ensure_uri()
  end

  defp subject_module(content) do
    uri = subject_module_uri()
    Document.new(uri, content, 1)
  end

  defp resolve(code) do
    with {position, code} <- pop_cursor(code),
         document = subject_module(code),
         analysis = Lexical.Ast.analyze(document),
         {:ok, resolved, range} <- Entity.resolve(analysis, position) do
      {:ok, resolved, decorate(document, range)}
    end
  end
end
