defmodule Lexical.Server.Provider.Handlers.GoToDefinitionTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Proto.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false

  setup_all do
    start_supervised(Document.Store)
    project = project(:navigations)

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    Dispatch.register(project, [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)

    assert_receive project_compiled(), 5000

    {:ok, project: project}
  end

  defp with_referenced_file(%{project: project}) do
    path = file_path(project, Path.join("lib", "my_definition.ex"))
    %{uri: Document.Path.ensure_uri(path)}
  end

  def build_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri],
      position: [line: line, character: char]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- build(GoToDefinition, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    Handlers.GoToDefinition.handle(request, %Env{project: project})
  end

  describe "go to definition" do
    setup [:with_referenced_file]

    test "find the function defintion", %{project: project, uri: referenced_uri} do
      uses_file_path = file_path(project, Path.join("lib", "uses.ex"))
      {:ok, request} = build_request(uses_file_path, 4, 17)

      {:reply, %{result: %Location{} = location}} = handle(request, project)

      assert location.range.start.line == 15
      assert location.range.start.character == 7
      assert location.range.end.line == 15
      assert location.range.end.character == 12
      assert Location.uri(location) == referenced_uri
    end
  end
end
