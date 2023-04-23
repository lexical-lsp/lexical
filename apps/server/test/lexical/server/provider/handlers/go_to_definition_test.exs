defmodule Lexical.Server.Provider.Handlers.GoToDefinitionTest do
  alias Lexical.Protocol.Requests.GoToDefinition
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers
  alias Lexical.SourceFile

  import Lexical.Protocol.Proto.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false

  setup_all do
    start_supervised(SourceFile.Store)
    project = project(:navigations)

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised(Lexical.RemoteControl.ProjectNodeSupervisor)
    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    Dispatch.register(project, [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)

    assert_receive project_compiled(), 5000

    on_exit(fn -> RemoteControl.stop(project) end)

    {:ok, project: project}
  end

  defp with_referenced_file(%{project: project}) do
    path = file_path(project, Path.join("lib", "my_definition.ex"))
    %{uri: SourceFile.Path.ensure_uri(path)}
  end

  def build_request(path, line, char) do
    uri = SourceFile.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri],
      position: [line: line, character: char]
    ]

    with {:ok, _} <- SourceFile.Store.open_temporary(uri),
         {:ok, req} <- build(GoToDefinition, params) do
      GoToDefinition.to_elixir(req)
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

      {:reply, %{result: %{range: range, uri: uri}}} = handle(request, project)

      assert range.start.line == 14
      assert range.start.character == 6
      assert range.end.line == 14
      assert range.end.character == 11
      assert uri == referenced_uri
    end
  end
end
