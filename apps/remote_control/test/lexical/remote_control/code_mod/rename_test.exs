defmodule Lexical.RemoteControl.CodeMod.RenameTest do
  alias Lexical.Document
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Proxy
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.CodeMod.Rename
  alias Lexical.RemoteControl.Commands.RenameSupervisor
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
  use Patch

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

  setup do
    patch(RenameSupervisor, :start_renaming, :ok)
    patch(Proxy, :start_buffering, :ok)
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

    test "returns the whole module name even if the cursor is not at the end" do
      {:ok, result, _} =
        ~q[
        defmodule Top|Level.Foo do
        end
      ] |> prepare()

      assert result == "TopLevel.Foo"
    end

    test "returns `nil` when renaming a module occurs in a reference." do
      assert {:ok, nil} =
               ~q[
        defmodule Foo do
        end

        defmodule Bar do
          alias |Foo
        end
      ] |> prepare()
    end

    test "returns error when the entity is not found" do
      assert {:error, "Renaming :variable is not supported for now"} =
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

  describe "rename module descendants" do
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

  describe "rename file" do
    setup do
      patch(Entity, :function_exists?, false)
      :ok
    end

    test "it shouldn't rename file if the module has parent module within that file" do
      {:ok, {_applied, nil}} =
        ~q[
        defmodule FooServer do
          defmodule |State do
          end
        end
        ] |> rename("Renamed", "lib/foo_server.ex")
    end

    test "it shouldn't rename file if the module has any siblings within that file" do
      assert {:ok, {_applied, nil}} =
               ~q[
        defmodule |Foo do
        end

        defmodule Bar do
        end
        ] |> rename("Renamed", "lib/foo.ex")
    end

    test "it shouldn't rename file if the path doesn't match the any convensions" do
      assert {:ok, {_applied, nil}} =
               ~q[
        defmodule |Foo.Mix do
        end
        ] |> rename("Renamed", "mix.ex")
    end

    test "succeeds when the path matching the `lib/*` convension", %{project: project} do
      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule |Foo do
        end
      ] |> rename("Renamed", "lib/foo.ex")

      assert rename_file.new_uri == subject_uri(project, "lib/renamed.ex")
    end

    test "it shouldn't rename file if just uppercased the module name" do
      assert {:ok, {_applied, nil}} =
               ~q[
        defmodule |Foo do
        end
        ] |> rename("FOO", "lib/foo.ex")
    end

    test "succeeds when the path matching the `apps/*` convension", %{project: project} do
      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule |FooApp.Bar do
        end
      ] |> rename("FooApp.Renamed", "apps/foo_app/lib/foo_app/bar.ex")

      assert rename_file.new_uri == subject_uri(project, "apps/foo_app/lib/foo_app/renamed.ex")
    end

    test "succeeds when the path matching the `apps/*` convension with nested folders", %{
      project: project
    } do
      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule |Lexical.RemoteControl do
        end
      ] |> rename("Lexical.RemoteChaos", "apps/remote_control/lib/lexical/remote_control.ex")

      assert rename_file.new_uri ==
               subject_uri(project, "apps/remote_control/lib/lexical/remote_chaos.ex")
    end

    test "succeeds when the path matching the `test/*` convension", %{project: project} do
      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule |FooTest do
        end
      ] |> rename("RenamedTest", "test/foo_test.exs")

      assert rename_file.new_uri == subject_uri(project, "test/renamed_test.exs")
    end

    test "leaves the `components` folder as is when renaming the live view", %{project: project} do
      patch(Entity, :phoenix_component_module?, fn DemoWeb.FooComponent -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.|FooComponent do
        end
      ] |> rename("DemoWeb.RenamedComponent", "lib/demo_web/components/foo_component.ex")

      assert rename_file.new_uri ==
               subject_uri(project, "lib/demo_web/components/renamed_component.ex")
    end

    test "leaves the `components` folder as is when renaming a component", %{project: project} do
      patch(Entity, :phoenix_component_module?, fn DemoWeb.SomeContext.FooComponent -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.SomeContext.|FooComponent do
        end
      ]
        |> rename(
          "DemoWeb.SomeContext.RenamedComponent",
          "lib/demo_web/components/some_context/foo_component.ex"
        )

      assert rename_file.new_uri ==
               subject_uri(project, "lib/demo_web/components/some_context/renamed_component.ex")
    end

    test "leaves the `components` folder as is when the user prefers to include the `Components` in the module name",
         %{
           project: project
         } do
      patch(Entity, :phoenix_component_module?, fn DemoWeb.Components.Icons -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.Components.|Icons do
        end
      ] |> rename("DemoWeb.Components.RenamedIcons", "lib/demo_web/components/icons.ex")

      assert rename_file.new_uri ==
               subject_uri(project, "lib/demo_web/components/renamed_icons.ex")
    end

    test "leaves the `controllers` folder as is when renaming the controller", %{project: project} do
      patch(Entity, :phoenix_controller_module?, fn DemoWeb.FooController -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.|FooController do
        end
      ] |> rename("DemoWeb.RenamedController", "lib/demo_web/controllers/foo_controller.ex")

      assert rename_file.new_uri ==
               subject_uri(project, "lib/demo_web/controllers/renamed_controller.ex")
    end

    test "leaves the `controller` folder as is when renaming the `JSON` module", %{
      project: project
    } do
      patch(Entity, :phoenix_controller_module?, fn DemoWeb.FooController.JSON -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.FooController.|JSON do
        end
      ]
        |> rename(
          "DemoWeb.FooController.RenamedJSON",
          "lib/demo_web/controllers/foo_controller/json.ex"
        )

      assert rename_file.new_uri ==
               subject_uri(project, "lib/demo_web/controllers/foo_controller/renamed_json.ex")
    end

    test "leaves the `live` folder as is when renaming the live view", %{project: project} do
      patch(Entity, :phoenix_liveview_module?, fn DemoWeb.FooLive -> true end)

      {:ok, {_applied, rename_file}} =
        ~q[
        defmodule DemoWeb.|FooLive do
        end
      ] |> rename("DemoWeb.RenamedLive", "lib/demo_web/live/foo_live.ex")

      assert rename_file.new_uri == subject_uri(project, "lib/demo_web/live/renamed_live.ex")
    end
  end

  defp rename(source, new_name, path \\ nil) do
    project = project()
    uri = subject_uri(project, path)

    with {position, text} <- pop_cursor(source),
         {:ok, document} <- open_document(uri, text),
         {:ok, entries} <- Search.Indexer.Source.index(document.path, text),
         :ok <- Search.Store.replace(entries),
         analysis = Lexical.Ast.analyze(document),
         {:ok, document_changes} <- Rename.rename(analysis, position, new_name, nil) do
      changes = document_changes |> Enum.map(& &1.edits) |> List.flatten()
      applied = apply_edits(document, changes)

      result =
        if path do
          rename_file = document_changes |> Enum.map(& &1.rename_file) |> List.first()
          {applied, rename_file}
        else
          applied
        end

      {:ok, result}
    end
  end

  defp prepare(code) do
    project = project()
    uri = subject_uri(project)

    with {position, text} <- pop_cursor(code),
         {:ok, document} <- open_document(uri, text),
         {:ok, entries} <- Search.Indexer.Source.index(document.path, text),
         :ok <- Search.Store.replace(entries) do
      analysis = Lexical.Ast.analyze(document)
      Rename.prepare(analysis, position)
    end
  end

  defp subject_uri(project, path \\ nil) do
    path = path || Path.join("wont_rename_file_folder", "project.ex")

    uri =
      project
      |> file_path(path)
      |> Document.Path.ensure_uri()

    on_exit(fn ->
      Document.Store.close(uri)
    end)

    uri
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
