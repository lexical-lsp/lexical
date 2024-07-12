defmodule Lexical.Server.Provider.Handlers.PrepareRenameTest do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.PrepareRename
  alias Lexical.RemoteControl

  alias Lexical.Server
  alias Lexical.Server.Configuration
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
         {:ok, req} <- build(PrepareRename, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    Handlers.PrepareRename.handle(request, %Configuration{project: project})
  end

  describe "prepare_rename" do
    test "returns error when document can not be analyzed", %{project: project, uri: uri} do
      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: false}}
      end)

      {:ok, request} = build_request(uri, 1, 5)
      assert {:reply, response} = handle(request, project)

      assert response.error.message == "document can not be analyzed"
    end

    test "returns nil when the cursor is not at a declaration", %{project: project, uri: uri} do
      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: true}}
      end)

      patch(RemoteControl.Api, :prepare_rename, fn ^project, _analysis, _position ->
        {:ok, nil}
      end)

      {:ok, request} = build_request(uri, 1, 5)
      assert {:reply, response} = handle(request, project)

      assert response.result == nil
    end

    test "returns error when the cursor entity is not supported", %{project: project, uri: uri} do
      patch(Document.Store, :fetch, fn ^uri, :analysis ->
        {:ok, nil, %Ast.Analysis{valid?: true}}
      end)

      patch(RemoteControl.Api, :prepare_rename, fn ^project, _analysis, _position ->
        {:error, "Renaming :map_field is not supported for now"}
      end)

      {:ok, request} = build_request(uri, 1, 5)
      assert {:reply, response} = handle(request, project)

      assert response.error.message == "Renaming :map_field is not supported for now"
    end
  end
end
