defmodule Lexical.RemoteControl.CodeIntelligence.RenameTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Rename
  alias Lexical.RemoteControl.Search

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
    RemoteControl.set_project(project)
    start_supervised!({Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]})

    start_supervised!(
      {Search.Store,
       [
         project,
         fn _ -> {:ok, []} end,
         fn _, _ -> {:ok, [], []} end,
         Search.Store.Backends.Ets
       ]}
    )

    assert_eventually Search.Store.loaded?()

    {:ok, project: project}
  end

  setup %{project: project} do
    uri = subject_uri(project)

    on_exit(fn ->
      Document.Store.close(uri)
    end)

    %{uri: uri}
  end

  describe "rename exact module" do
    test "succeeds when the cursor on the definition" do
      {:ok, result} =
        ~q[
        defmodule |Foo do
        end
      ] |> rename("Renamed")

      assert result =~ ~S[defmodule Renamed do]
    end

    test "succeeds when the cursor on the alias" do
      {:ok, result} =
        ~q[
        defmodule Baz do
          alias |Foo
        end
      ] |> rename("Renamed")

      assert result =~ ~S[alias Renamed]
    end

    test "succeeds when the definition in a nested module" do
      {:ok, result} =
        ~q[
        defmodule TopLevel do
          defmodule Foo do
          end
        end

        defmodule TopLevelTest do
          alias TopLevel.|Foo
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

    test "succeeds when the cursor in the multiple aliases off of single alias" do
      {:ok, result} =
        ~q[
        defmodule TopLevel do
          alias Foo.{
            First, Second,
            Third.Fourth
          }
          |Second
        end
      ] |> rename("Renamed")

      assert result =~ ~S[  First, Renamed,]
    end

    test "only rename the aliased when the cursor at the aliased" do
      {:ok, result} =
        ~q[
        defmodule TopLevel do
          alias Foo.Bar, as: FooBar
          |FooBar
        end
        ]
        |> rename("Renamed")

      assert result =~ ~S[alias Foo.Bar, as: Renamed]
      assert result =~ ~S[  Renamed]
    end

    test "succeeds when the cursor at the alias_ased child" do
      {:ok, result} =
        ~q[
          defmodule TopLevel.Foo.Bar do
          end

          defmodule TopLevel.Another do
            alias TopLevel.Foo, as: Parent
            Parent.|Bar
          end
        ]
        |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Foo.Renamed]

      assert result =~ ~S[  Parent.Renamed]
    end

    test "only rename aliased when the cursor at the alias_ased" do
      {:ok, result} =
        ~q[
          defmodule TopLevel.Foo.Bar do
          end

          defmodule TopLevel.Another do
            alias TopLevel.Foo, as: Parent
            |Parent.Bar
          end
        ]
        |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Foo.Bar do]

      assert result =~ ~S[alias TopLevel.Foo, as: Renamed]
      assert result =~ ~S[  Renamed.Bar]
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

    test "shouldn't rename the descendants when the cursor at the end of the module" do
      {:ok, result} = ~q[
        defmodule TopLevel.Module do # ✓
        end

        defmodule TopLevel.Module.Another do # x
          alias TopLevel.|Module
        end
      ] |> rename("Renamed")

      refute result =~ ~S[defmodule TopLevel.Renamed.Another]

      assert result =~ ~S[defmodule TopLevel.Renamed do]
      assert result =~ ~S[alias TopLevel.Renamed]
    end
  end

  describe "rename descendants" do
    test "in the middle of definition" do
      {:ok, result} =
        ~q[
          defmodule TopLevel.|Middle.Module do
            alias TopLevel.Middle.Module
          end
        ] |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Renamed.Module]
      assert result =~ ~S[alias TopLevel.Renamed.Module]
    end

    test "in the middle of reference" do
      {:ok, result} =
        ~q[
          defmodule TopLevel.Second.Middle.Module do
            alias TopLevel.Second.|Middle.Module
          end
        ] |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Second.Renamed.Module]
      assert result =~ ~S[alias TopLevel.Second.Renamed.Module]
    end

    test "succeeds when there are same module name in the cursor neighborhood" do
      {:ok, result} =
        ~q[
          defmodule TopLevel.Foo do
          end

          defmodule TopLevel.Foo.Foo do
          end

          defmodule TopLevel.Another do
            alias TopLevel.Foo.|Foo
          end
        ] |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Foo do]
      assert result =~ ~S[defmodule TopLevel.Foo.Renamed do]
      assert result =~ ~S[alias TopLevel.Foo.Renamed]
    end

    test "succeeds even if there are descendants with the same name" do
      {:ok, result} =
        ~q[
        defmodule TopLevel.Foo do
          defmodule Foo do # skip this
          end
        end

        defmodule TopLevel.Bar do
          alias TopLevel.|Foo.Foo
        end
      ]
        |> rename("Renamed")

      assert result =~ ~S[defmodule TopLevel.Renamed do]
      assert result =~ ~S[defmodule Foo do # skip this]
      assert result =~ ~S[alias TopLevel.Renamed.Foo]
    end
  end

  describe "rename struct" do
    test "succeeds when the cursor on the definition" do
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

    test "succeeds when the cursor on the reference" do
      {:ok, result} =
        ~q[
        defmodule Foo do
          defstruct bar: 1
        end

        defmodule Bar do
          def foo do
            %Fo|o{}
          end
        end
      ] |> rename("Renamed")

      assert result =~ ~S[defmodule Renamed do]
      assert result =~ ~S[defmodule Bar do]
      assert result =~ ~S[%Renamed{}]
    end
  end

  describe "unsupported" do
    test "rename a function" do
      assert {:error, {:unsupported, {:local_or_var, ~c"bar"}}} ==
               ~q[
        defmodule Foo do
          def |bar do
          end
        end
      ] |> rename("baz")
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
