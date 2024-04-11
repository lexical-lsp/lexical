defmodule Lexical.Server.Provider.Handlers.RenameTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.Rename
  alias Lexical.RemoteControl

  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false
  use Patch

  setup_all do
    start_supervised(Server.Application.document_store_child_spec())
    :ok
  end

  setup do
    project = project(:navigations)
    path = file_path(project, Path.join("lib", "my_definition.ex"))
    uri = Document.Path.ensure_uri(path)
    {:ok, project: project, uri: uri}
  end

  def build_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri],
      position: [line: line, character: char]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- build(Rename, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    Handlers.Rename.handle(request, %Env{project: project})
  end

  describe "rename" do
    test "returns nil when document can not be analyzed", %{project: project, uri: uri} do
      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: false}}
      end)

      {:ok, request} = build_request(uri, 1, 5)
      assert {:reply, response} = handle(request, project)

      assert response.error.message == "document can not be analyzed"
    end

    test "returns nil when there are no changes", %{project: project, uri: uri} do
      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: true}}
      end)

      patch(RemoteControl.Api, :rename, fn ^project, _analysis, _position, _new_name, _ ->
        {:ok, []}
      end)

      {:ok, request} = build_request(uri, 1, 5)
      assert {:reply, response} = handle(request, project)

      assert response == nil
    end

    test "returns edit when there are changes", %{project: project, uri: uri} do
      document = %Document{uri: uri, version: 0}

      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: true}}
      end)

      patch(RemoteControl.Api, :rename, fn ^project, _analysis, _position, _new_name, _ ->
        {:ok,
         [
           Document.Changes.new(
             document,
             [
               %{
                 new_text: "new_text",
                 range: %{start: %{line: 1, character: 5}, end: %{line: 1, character: 10}}
               }
             ],
             Document.Changes.RenameFile.new(
               document.uri,
               "file:///path/to/new_text.ex"
             )
           )
         ]}
      end)

      {:ok, request} = build_request(uri, 1, 5)

      assert {:reply, response} = handle(request, project)
      [edit, rename_file] = response.result.document_changes

      assert edit.edits == [
               %{
                 new_text: "new_text",
                 range: %{end: %{character: 10, line: 1}, start: %{character: 5, line: 1}}
               }
             ]

      assert edit.text_document.uri == document.uri
      assert edit.text_document.version == 0
      assert rename_file.old_uri == document.uri
      assert rename_file.new_uri == "file:///path/to/new_text.ex"
    end
  end
end
