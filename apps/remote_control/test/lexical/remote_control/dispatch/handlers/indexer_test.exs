defmodule Lexical.RemoteControl.Dispatch.Handlers.IndexingTest do
  alias Lexical.Document
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.Commands
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

    start_supervised!(RemoteControl.Dispatch)
    start_supervised!(Commands.Reindex)
    start_supervised!({Search.Store, [project, create_index, update_index]})
    start_supervised!({Document.Store, derive: [analysis: &Lexical.Ast.analyze/1]})

    Search.Store.enable()
    assert_eventually(Search.Store.loaded?(), 1500)

    {:ok, state} = Indexing.init([])
    {:ok, state: state, project: project}
  end

  def set_document!(source) do
    uri = "file:///file.ex"

    :ok =
      case Document.Store.fetch(uri) do
        {:ok, _} ->
          Document.Store.update(uri, fn doc ->
            edit = Document.Edit.new(source)
            Document.apply_content_changes(doc, doc.version + 1, [edit])
          end)

        {:error, :not_open} ->
          Document.Store.open(uri, source, 1)
      end

    {uri, source}
  end

  describe "handling file_quoted events" do
    test "should add new entries to the store", %{state: state} do
      {uri, _source} =
        ~q[
          defmodule NewModule do
          end
        ]
        |> set_document!()

      assert {:ok, _} = Indexing.on_event(file_compile_requested(uri: uri), state)

      assert_eventually {:ok, [entry]} = Search.Store.exact("NewModule", [])

      assert entry.subject == NewModule
    end

    test "should update entries in the store", %{state: state} do
      {uri, source} =
        ~q[
          defmodule OldModule
          end
        ]
        |> set_document!()

      {:ok, _} = Search.Indexer.Source.index(uri, source)

      {^uri, _source} =
        ~q[
          defmodule UpdatedModule do
          end
        ]
        |> set_document!()

      assert {:ok, _} = Indexing.on_event(file_compile_requested(uri: uri), state)

      assert_eventually {:ok, [entry]} = Search.Store.exact("UpdatedModule", [])
      assert entry.subject == UpdatedModule
      assert {:ok, []} = Search.Store.exact("OldModule", [])
    end

    test "only updates entries if the version of the document is the same as the version in the document store",
         %{state: state} do
      Document.Store.open("file:///file.ex", "defmodule Newer do \nend", 3)

      {uri, _source} =
        ~q[
          defmodule Stale do
          end
        ]
        |> set_document!()

      assert {:ok, _} = Indexing.on_event(file_compile_requested(uri: uri), state)
      assert {:ok, []} = Search.Store.exact("Stale", [])
    end
  end

  describe "a file is deleted" do
    test "its entries should be deleted", %{project: project, state: state} do
      {uri, source} =
        ~q[
          defmodule ToDelete do
          end
        ]
        |> set_document!()

      {:ok, entries} = Search.Indexer.Source.index(uri, source)
      Search.Store.update(uri, entries)

      assert_eventually {:ok, [_]} = Search.Store.exact("ToDelete", [])

      Indexing.on_event(
        filesystem_event(project: project, uri: uri, event_type: :deleted),
        state
      )

      assert_eventually {:ok, []} = Search.Store.exact("ToDelete", [])
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
