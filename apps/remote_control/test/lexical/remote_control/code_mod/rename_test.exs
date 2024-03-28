defmodule Lexical.RemoteControl.CodeMod.RenameTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeMod.Rename
  alias Lexical.RemoteControl.Search
  alias Lexical.RemoteControl.Search.Store.Backends
  alias Lexical.Test.CodeSigil
  alias Lexical.Test.CursorSupport
  alias Lexical.Test.Fixtures

  import CodeSigil
  import CursorSupport
  import Lexical.Test.EventualAssertions
  import Fixtures

  use ExUnit.Case

  setup_all do
    project = project()

    Backends.Ets.destroy_all(project)
    RemoteControl.set_project(project)

    start_supervised!({Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]})
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

  setup %{project: project} do
    uri = subject_uri(project)

    on_exit(fn ->
      Document.Store.close(uri)
    end)

    %{uri: uri}
  end

  describe "prepare/2" do
    test "returns the module name" do
      {:ok, result, _} =
        ~q[
        defmodule |Foo do
        end
      ] |> prepare()

      assert result == "Foo"
    end

    test "returns the whole module name" do
      {:ok, result, _} =
        ~q[
        defmodule TopLevel.|Foo do
        end
      ] |> prepare()

      assert result == "TopLevel.Foo"
    end

    test "returns the whole module name even if the cusor is not at the end" do
      {:ok, result, _} =
        ~q[
        defmodule Top|Level.Foo do
        end
      ] |> prepare()

      assert result == "TopLevel.Foo"
    end

    test "returns location error when renaming a module occurs in a reference." do
      assert {:error, {:unsupported_location, :module}} ==
               ~q[
        defmodule Foo do
        end

        defmodule Bar do
          alias |Foo
        end
      ] |> prepare()
    end

    test "returns error when the entity is not found" do
      assert {:error, :unsupported_entity} =
               ~q[
          x = 1
          |x
      ] |> prepare()
    end
  end

  describe "rename exact module" do
    test "succeeds when the cursor is at the definition" do
      {:ok, result} =
        ~q[
        defmodule |Foo do
        end
      ] |> rename("Renamed")

      assert result =~ ~S[defmodule Renamed do]
    end

    test "failed when the cursor is at the alias" do
      assert {:error, {:unsupported_location, :module}} ==
               ~q[
        defmodule Baz do
          alias |Foo
        end
      ] |> rename("Renamed")
    end

    test "failed when the cursor is not at reference" do
      assert {:error, {:unsupported_location, :module}} ==
               ~q[
        defmodule TopLevel.Context do
          alias TopLevel.Baz
          Ba|z.foo()
        end
      ] |> rename("Renamed")
    end

    test "succeeds when the module has multiple dots" do
      {:ok, result} = ~q[
        defmodule TopLevel.Foo.|Bar do
        end
      ] |> rename("TopLevel.Foo.Renamed")

      assert result =~ ~S[defmodule TopLevel.Foo.Renamed do]
    end

    test "succeeds when renaming the middle part of the module" do
      {:ok, result} =
        ~q[
        defmodule TopLevel.Foo.|Bar do
        end
      ] |> rename("TopLevel.Renamed.Bar")

      assert result =~ ~S[defmodule TopLevel.Renamed.Bar do]
    end

    test "succeeds when simplifing the module name" do
      {:ok, result} =
        ~q[
        defmodule TopLevel.Foo.|Bar do
        end
      ] |> rename("TopLevel.Renamed")

      assert result =~ ~S[defmodule TopLevel.Renamed do]
    end

    test "succeeds when the definition is in a nested module" do
      {:ok, result} =
        ~q[
        defmodule TopLevel do
          defmodule |Foo do
          end
        end

        defmodule TopLevelTest do
          alias TopLevel.Foo
        end
      ] |> rename("Renamed")

      assert result == ~q[
        defmodule TopLevel do
          defmodule Renamed do
          end
        end

        defmodule TopLevelTest do
          alias TopLevel.Renamed
        end
      ]
    end

    test "succeeds when the cursor is in the multiple aliases off of single alias" do
      {:ok, result} =
        ~q[
        defmodule Foo.|Second do
        end

        defmodule TopLevel do
          alias Foo.{
            First, Second,
            Third.Fourth
          }
        end
      ] |> rename("Foo.Renamed")

      assert result =~ ~S[  First, Renamed,]
    end

    test "shouldn't rename the relative module" do
      {:ok, result} =
        ~q[
        defmodule |Foo do
        end

        defmodule FooTest do
        end
        ] |> rename("Renamed")

      assert result =~ ~S[defmodule FooTest do]
    end
  end

  describe "rename descendants" do
    test "rename the descendants" do
      {:ok, result} = ~q[
        defmodule TopLevel.|Module do
        end

        defmodule TopLevel.Module.Another do
        end
      ] |> rename("TopLevel.Renamed")

      assert result =~ ~S[defmodule TopLevel.Renamed.Another]
      assert result =~ ~S[defmodule TopLevel.Renamed do]
    end

    test "succeeds rename the descendants when expanding the module name" do
      {:ok, result} = ~q[
        defmodule TopLevel.|Module do
          alias TopLevel.Module.Another
        end

        defmodule TopLevel.Module.Another do
        end
      ] |> rename("TopLevel.ModuleRenamed")

      assert result =~ ~S[defmodule TopLevel.ModuleRenamed]
      assert result =~ ~S[alias TopLevel.ModuleRenamed.Another]
      assert result =~ ~S[defmodule TopLevel.ModuleRenamed.Another do]
    end

    test "succeeds when expanding the module name with multiple dots" do
      {:ok, result} =
        ~q[
        defmodule TopLevel.|Bar do
        end

        defmodule TopLevel.Bar.Baz do
        end

        defmodule TopLevel.BarTest do
          alias TopLevel.Bar
          alias TopLevel.Bar.Baz
        end
      ] |> rename("TopLevel.Bar.Renamed")

      assert result =~ ~S[defmodule TopLevel.Bar.Renamed do]
      assert result =~ ~S[alias TopLevel.Bar.Renamed]
      assert result =~ ~S[alias TopLevel.Bar.Renamed.Baz]
    end

    test "succeeds when there are same module name is in the cursor neighborhood" do
      {:ok, result} =
        ~q[
          defmodule Foo.Bar.Foo.|Bar do
          end

          defmodule Foo.Bar.Foo.Bar.Baz do
          end

          defmodule TopLevel.Another do
            alias Foo.Bar.Foo.Bar.Baz
          end
        ] |> rename("Foo.Bar.Foo.Renamed")

      assert result =~ ~S[defmodule Foo.Bar.Foo.Renamed do]
      assert result =~ ~S[defmodule Foo.Bar.Foo.Renamed.Baz do]
      assert result =~ ~S[alias Foo.Bar.Foo.Renamed.Baz]
    end

    test "succeeds even if there are descendants with the same name" do
      {:ok, result} =
        ~q[
        defmodule TopLevel.|Foo do
          defmodule Foo do # skip this
          end
        end

        defmodule TopLevel.Bar do
          alias TopLevel.Foo.Foo
        end
      ]
        |> rename("TopLevel.Renamed")

      assert result =~ ~S[defmodule TopLevel.Renamed do]
      assert result =~ ~S[defmodule Foo do # skip this]
      assert result =~ ~S[alias TopLevel.Renamed.Foo]
    end

    test "it shouldn't rename the descendant module if the module only contains old suffix" do
      {:ok, result} =
        ~q[
        defmodule |TopLevel.Ast do
        end

        defmodule TopLevel.AnotherModule do
          alias TopLevel.Ast.Detection

          Detection.Bitstring.detected?() # Bitstring contains the old suffix: `st`
        end
      ] |> rename("TopLevel.AST")

      refute result =~ ~S[Detection.BitSTring.detected?()]
    end
  end

  describe "rename struct" do
    test "succeeds when the cursor is at the definition" do
      {:ok, result} =
        ~q[
        defmodule |Foo do
          defstruct bar: 1
        end

        defmodule Bar do
          def foo do
            %Foo{}
          end
        end
      ] |> rename("Renamed")

      assert result =~ ~S[defmodule Renamed do]
      assert result =~ ~S[%Renamed{}]
    end
  end

  defp rename(%Project{} = project \\ project(), source, new_name) do
    uri = subject_uri(project)

    with {position, text} <- pop_cursor(source),
         {:ok, document} <- open_document(uri, text),
         {:ok, entries} <- Search.Indexer.Source.index(document.path, text),
         :ok <- Search.Store.replace(entries),
         analysis = Lexical.Ast.analyze(document),
         {:ok, uri_with_changes} <- Rename.rename(analysis, position, new_name) do
      changes = uri_with_changes |> Map.values() |> List.flatten()
      {:ok, apply_edits(document, changes)}
    end
  end

  defp prepare(project \\ project(), code) do
    uri = subject_uri(project)

    with {position, text} <- pop_cursor(code),
         {:ok, document} <- open_document(uri, text),
         {:ok, entries} <- Search.Indexer.Source.index(document.path, text),
         :ok <- Search.Store.replace(entries),
         analysis = Lexical.Ast.analyze(document),
         {:ok, result} <- Rename.prepare(analysis, position) do
      result
    end
  end

  defp subject_uri(project) do
    project
    |> file_path(Path.join("lib", "project.ex"))
    |> Document.Path.ensure_uri()
  end

  defp open_document(uri, content) do
    with :ok <- Document.Store.open(uri, content, 0) do
      Document.Store.fetch(uri)
    end
  end

  def apply_edits(document, text_edits) do
    {:ok, edited_document} = Document.apply_content_changes(document, 1, text_edits)
    edited_document = Document.to_string(edited_document)
    edited_document
  end
end
