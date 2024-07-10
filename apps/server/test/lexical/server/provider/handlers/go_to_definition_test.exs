defmodule Lexical.Server.Provider.Handlers.GoToDefinitionTest do
  alias Lexical.Document
  alias Lexical.Document.Location
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false

  setup_all do
    project = project(:navigations)

    start_supervised!(Server.Application.document_store_child_spec())
    start_supervised!({DynamicSupervisor, Server.Project.Supervisor.options()})
    start_supervised!({Server.Project.Supervisor, project})

    RemoteControl.Api.register_listener(project, self(), [
      project_compiled(),
      project_index_ready()
    ])

    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000
    assert_receive project_index_ready(), 5000

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
    config = Server.Configuration.new(project: project)
    Handlers.GoToDefinition.handle(request, config)
  end

  describe "go to definition" do
    setup [:with_referenced_file]

    test "finds user-defined functions", %{project: project, uri: referenced_uri} do
      uses_file_path = file_path(project, Path.join("lib", "uses.ex"))
      {:ok, request} = build_request(uses_file_path, 4, 17)

      {:reply, %{result: %Location{} = location}} = handle(request, project)
      assert Location.uri(location) == referenced_uri
    end

    test "finds user-defined modules", %{project: project, uri: referenced_uri} do
      uses_file_path = file_path(project, Path.join("lib", "uses.ex"))
      {:ok, request} = build_request(uses_file_path, 4, 4)

      {:reply, %{result: %Location{} = location}} = handle(request, project)
      assert Location.uri(location) == referenced_uri
    end

    test "does not find built-in functions", %{project: project} do
      uses_file_path = file_path(project, Path.join("lib", "uses.ex"))
      {:ok, request} = build_request(uses_file_path, 8, 7)

      {:reply, %{result: nil}} = handle(request, project)
    end

    test "does not find built-in modules", %{project: project} do
      uses_file_path = file_path(project, Path.join("lib", "uses.ex"))
      {:ok, request} = build_request(uses_file_path, 8, 4)

      {:reply, %{result: nil}} = handle(request, project)
    end
  end
end
