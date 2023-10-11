defmodule Lexical.Server.Provider.Handlers.FindReferencesTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.FindReferences
  alias Lexical.Protocol.Responses
  alias Lexical.Server.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false
  use Patch

  setup_all do
    start_supervised!(Document.Store)
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
         {:ok, req} <- build(FindReferences, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    Handlers.FindReferences.handle(request, %Env{project: project})
  end

  describe "find references" do
    test "returns locations that the entity returns", %{project: project, uri: uri} do
      patch(Entity, :references, fn ^project, document, _position ->
        locations = [
          Location.new(
            Document.Range.new(
              Document.Position.new(document, 1, 5),
              Document.Position.new(document, 1, 10)
            ),
            Document.Path.to_uri("/path/to/file.ex")
          )
        ]

        {:ok, locations}
      end)

      {:ok, request} = build_request(uri, 5, 6)

      assert {:reply, %Responses.FindReferences{} = response} = handle(request, project)
      assert [%Location{} = location] = response.result
      assert location.uri =~ "file.ex"
    end

    test "returns nothing if the entity can't resolve it", %{project: project, uri: uri} do
      patch(Entity, :references, {:error, :not_found})

      {:ok, request} = build_request(uri, 1, 5)

      assert {:reply, %Responses.FindReferences{} = response} = handle(request, project)
      assert response.result == nil
    end
  end
end
