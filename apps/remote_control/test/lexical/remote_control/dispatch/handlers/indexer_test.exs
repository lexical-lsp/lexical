defmodule Lexical.RemoteControl.Dispatch.Handlers.IndexingTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.Dispatch.Handlers.Indexing
  alias Lexical.RemoteControl.Search

  import Api.Messages
  import Lexical.Test.CodeSigil
  import Lexical.Test.EventualAssertions
  import Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch

  setup do
    project = project()
    RemoteControl.set_project(project)
    create_index = &Search.Indexer.create_index/1
    update_index = &Search.Indexer.update_index/2

    start_supervised!({Search.Store, [project, create_index, update_index]})
    start_supervised!(Document.Store)

    assert_eventually(Search.Store.loaded?(), 1500)

    {:ok, state} = Indexing.init([])
    {:ok, state: state, project: project}
  end

  def quoted_document(source) do
    doc = Document.new("file:///file.ex", source, 1)
    Document.Store.open("file:///file.ex", source, 1)
    {:ok, quoted} = Ast.from(doc)

    {doc, quoted}
  end

  def file_quoted_event(document, quoted_ast) do
    file_quoted(document: document, quoted_ast: quoted_ast)
  end

  describe "handling file_quoted events" do
    test "should add new entries to the store", %{state: state} do
      {doc, quoted} =
        ~q[
          defmodule NewModule do
          end
        ]
        |> quoted_document()

      assert {:ok, _} = Indexing.on_event(file_quoted_event(doc, quoted), state)

      assert {:ok, [entry]} = Search.Store.exact("NewModule", [])

      assert entry.subject == NewModule
    end

    test "should update entries in the store", %{state: state} do
      {old_doc, old_quoted} = quoted_document("defmodule OldModule do\nend")

      {:ok, _} = Search.Indexer.Quoted.index(old_doc, old_quoted)

      {doc, quoted} =
        ~q[
        defmodule UpdatedModule do
        end
      ]
        |> quoted_document()

      assert {:ok, _} = Indexing.on_event(file_quoted_event(doc, quoted), state)

      assert {:ok, [entry]} = Search.Store.exact("UpdatedModule", [])
      assert entry.subject == UpdatedModule
      assert {:ok, []} = Search.Store.exact("OldModule", [])
    end

    test "only updates entries if the version of the document is the same as the version in the document store",
         %{state: state} do
      Document.Store.open("file:///file.ex", "defmodule Newer do \nend", 3)

      {doc, quoted} =
        ~q[
        defmodule Stale do
        end
      ]
        |> quoted_document()

      assert {:ok, _} = Indexing.on_event(file_quoted_event(doc, quoted), state)
      assert {:ok, []} = Search.Store.exact("Stale", [])
    end
  end

  describe "a file is deleted" do
    test "its entries should be deleted", %{project: project, state: state} do
      {doc, quoted} =
        ~q[
        defmodule ToDelete do
        end
      ]
        |> quoted_document()

      {:ok, entries} = Search.Indexer.Quoted.index(doc, quoted)
      Search.Store.update(doc.path, entries)
      assert {:ok, [_]} = Search.Store.exact("ToDelete", [])

      Indexing.on_event(
        filesystem_event(project: project, uri: doc.uri, event_type: :deleted),
        state
      )

      assert {:ok, []} = Search.Store.exact("ToDelete", [])
    end
  end

  describe "a file is created" do
    test "is a no op", %{project: project, state: state} do
      spy(Search.Store)
      spy(Search.Indexer)

      event = filesystem_event(project: project, uri: "file:///another.ex", event_type: :created)

      assert {:ok, _} = Indexing.on_event(event, state)

      assert history(Search.Store) == []
      assert history(Search.Indexer) == []
    end
  end
end
