defmodule Lexical.RemoteControl.CodeIntelligence.ReferencesTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.References
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Store.Backends

  use ExUnit.Case, async: false

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures
  import Lexical.Test.RangeSupport
  import Lexical.Test.EventualAssertions

  setup do
    project = project()

    Backends.Ets.destroy_all(project)
    RemoteControl.set_project(project)

    start_supervised!(Document.Store)
    start_supervised!(RemoteControl.Dispatch)
    start_supervised!(Backends.Ets)

    start_supervised!(
      {Search.Store, [project, fn _ -> {:ok, []} end, fn _, _ -> {:ok, [], []} end, Backends.Ets]}
    )

    Search.Store.enable()
    assert_eventually Search.Store.loaded?(), 1500

    on_exit(fn ->
      Backends.Ets.destroy_all(project)
    end)

    {:ok, project: project}
  end

  defp module_uri(project) do
    project
    |> file_path(Path.join("lib", "my_module.ex"))
    |> Document.Path.ensure_uri()
  end

  defp project_module(project, content) do
    uri = module_uri(project)

    with :ok <- Document.Store.open(uri, content, 1) do
      Document.Store.fetch(uri)
    end
  end

  describe "module references" do
    # Note: These tests aren't exhaustive, as that is covered by Search.StoreTest.
    test "are found in an alias", %{project: project} do
      code = ~q[
        defmodule ReferencesInAlias do
          alias ReferencedModule
        end
      ]

      assert {:ok, [%Location{} = location]} = references(project, "ReferencedModule|", code)
      assert decorate(code, location.range) =~ ~s[alias «ReferencedModule»]
    end

    test "are found in a module attribute", %{project: project} do
      code = ~q[
        defmodule ReferenceInAttribute do
          @attr ReferencedModule
        end
      ]

      assert {:ok, [%Location{} = location]} = references(project, "ReferencedModule|", code)
      assert decorate(code, location.range) =~ ~s[@attr «ReferencedModule»]
    end

    test "are found in a variable", %{project: project} do
      code = ~q[
        some_module = ReferencedModule
      ]

      assert {:ok, [%Location{} = location]} = references(project, "ReferencedModule|", code)
      assert decorate(code, location.range) =~ ~s[some_module = «ReferencedModule»]
    end

    test "are found in a function's parameters", %{project: project} do
      code = ~q[
        def some_fn(ReferencedModule) do
        end
      ]

      assert {:ok, [%Location{} = location]} = references(project, "ReferencedModule|", code)
      assert decorate(code, location.range) =~ ~s[def some_fn(«ReferencedModule») do]
    end

    test "includes struct definitions", %{project: project} do
      code = ~q[
        %ReferencedModule{} = something_else
      ]

      assert {:ok, [%Location{} = location]} = references(project, "ReferencedModule|", code)
      assert decorate(code, location.range) =~ ~s[%«ReferencedModule»{} = something_else]
    end

    test "includes definitions if the parameter is true", %{project: project} do
      code = ~q[
        defmodule DefinedModule do
        end

        defmodule OtherModule do
          @attr DefinedModule
        end
      ]

      assert {:ok, [location_1, location_2]} = references(project, "DefinedModule|", code, true)
      assert decorate(code, location_1.range) =~ ~s[defmodule «DefinedModule» do]
      assert decorate(code, location_2.range) =~ ~s[@attr «DefinedModule»]
    end
  end

  describe "struct references" do
    test "includes their definition if the parameter is true", %{project: project} do
      code = ~q(
      defmodule Struct do
        defstruct [:field]
      end
      )

      assert {:ok, [location]} = references(project, "%Struct|{}", code, true)
      assert decorate(code, location.range) =~ "«defstruct [:field]»"
    end

    test "excludes their definition", %{project: project} do
      code = ~q(
      defmodule Struct do
        defstruct [:field]
      end
      )

      assert {:ok, []} = references(project, "%Struct|{}", code)
    end
  end

  describe "module attribute references" do
    test "are found in a module", %{project: project} do
      code = ~q[
      defmodule Refs do
        @attr 3

        def fun(@attr), do: true
      end
      ]

      query = ~q[
      defmodule Refs do
        @att|r 3
      end

      ]

      assert {:ok, [reference]} = references(project, query, code)
      assert decorate(code, reference.range) =~ "  def fun(«@attr»), do: true"
    end

    test "includes definitions if the parameter is true", %{project: project} do
      code = ~q[
      defmodule Refs do
        @attr 3

        def fun(@attr), do: true
      end
      ]

      query = ~q[
      defmodule Refs do
        @att|r 3
      end

      ]

      assert {:ok, [definition, reference]} = references(project, query, code, true)
      assert decorate(code, definition.range) =~ "«@attr 3»"
      assert decorate(code, reference.range) =~ "  def fun(«@attr»), do: true"
    end
  end

  defp references(project, referenced, code, include_definitions? \\ false) do
    with {position, referenced} <- pop_cursor(referenced, as: :document),
         {:ok, document} <- project_module(project, code),
         {:ok, entries} <- Search.Indexer.Source.index(document.path, code),
         :ok <- Search.Store.replace(entries) do
      referenced
      |> Lexical.Ast.analyze()
      |> References.references(position, include_definitions?)
    end
  end
end
